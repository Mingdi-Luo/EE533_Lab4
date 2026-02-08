///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
// $Id: module_template 2008-03-13 gac1 $
//
// Module: ids.v
// Project: NF2.1
// Description: Defines a simple ids module for the user data path.  The
// modules reads a 64-bit register that contains a pattern to match and
// counts how many packets match.  The register contents are 7 bytes of
// pattern and one byte of mask.  The mask bits are set to one for each
// byte of the pattern that should be included in the mask -- zero bits
// mean "don't care".
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module ids #(
      parameter DATA_WIDTH = 64,
      parameter CTRL_WIDTH = DATA_WIDTH/8,
      parameter UDP_REG_SRC_WIDTH = 2
) (
   input  [DATA_WIDTH-1:0]  in_data,
   input  [CTRL_WIDTH-1:0]  in_ctrl,
   input                    in_wr,
   output                   in_rdy,

   output [DATA_WIDTH-1:0]  out_data,
   output [CTRL_WIDTH-1:0]  out_ctrl,
   output                   out_wr,
   input                    out_rdy,
   
   // --- Register interface
   input                               reg_req_in,
   input                               reg_ack_in,
   input                               reg_rd_wr_L_in,
   input  [`UDP_REG_ADDR_WIDTH-1:0]    reg_addr_in,
   input  [`CPCI_NF2_DATA_WIDTH-1:0]   reg_data_in,
   input  [UDP_REG_SRC_WIDTH-1:0]      reg_src_in,

   output                              reg_req_out,
   output                              reg_ack_out,
   output                              reg_rd_wr_L_out,
   output [`UDP_REG_ADDR_WIDTH-1:0]    reg_addr_out,
   output [`CPCI_NF2_DATA_WIDTH-1:0]   reg_data_out,
   output [UDP_REG_SRC_WIDTH-1:0]      reg_src_out,

   // misc
   input                               reset,
   input                               clk
);

   // Define the log2 function
   // `LOG2_FUNC
   function integer calc_log2;
      input integer value;
      integer i;
      begin
         i = 0;
         while (2**i < value) begin
            i = i + 1;
         end
         calc_log2 = i;
      end
   endfunction

   //------------------------- Signals-------------------------------

   wire [DATA_WIDTH-1:0] in_fifo_data;
   wire [CTRL_WIDTH-1:0] in_fifo_ctrl;

   wire                  in_fifo_nearly_full;
   wire                  in_fifo_empty;

   reg                   in_fifo_rd_en;
   reg                   out_wr_int;

   // software registers
   wire [31:0]           pattern_high;
   wire [31:0]           pattern_low;
   wire [31:0]           ids_cmd;
   // hardware registers
   reg  [31:0]           matches;

   // internal state
   reg [1:0]             state, state_next;
   reg [31:0]            matches_next;
   reg                   in_pkt_body, in_pkt_body_next;
   reg                   end_of_pkt, end_of_pkt_next;
   reg                   begin_pkt, begin_pkt_next;
   reg [2:0]             header_counter, header_counter_next;

   wire                  matcher_match;
   wire                  matcher_reset;
   wire                  matcher_en, matcher_ce;

   //------------------------------------------------------------
   // State machine parameters
   //------------------------------------------------------------
   parameter START   = 2'b00;
   parameter HEADER  = 2'b01;
   parameter PAYLOAD = 2'b10;

   //------------------------------------------------------------
   // Logic Analyzer
   //------------------------------------------------------------
   localparam CAPTURE_MEM_SIZE   = 256;
   localparam CAPTURE_ADDR_WIDTH = calc_log2(CAPTURE_MEM_SIZE);
   localparam FIFO_WORD_WIDTH = CTRL_WIDTH + DATA_WIDTH;  // i.e. 72
   localparam IN_FIFO_WORD_WIDTH  = FIFO_WORD_WIDTH;      // 72 bits
   localparam OUT_FIFO_WORD_WIDTH = FIFO_WORD_WIDTH;      // 72 bits

   reg [IN_FIFO_WORD_WIDTH-1:0]  in_fifo_mem  [0:CAPTURE_MEM_SIZE-1];
   reg [OUT_FIFO_WORD_WIDTH-1:0] out_fifo_mem [0:CAPTURE_MEM_SIZE-1];

   // Write pointers (saturating)
   reg [CAPTURE_ADDR_WIDTH-1:0] in_fifo_w_ptr;
   reg [CAPTURE_ADDR_WIDTH-1:0] out_fifo_w_ptr;

   // READ Related registers
   wire [31:0] la_in_read_ptr;   // SW read pointer for in_fifo_mem
   wire [31:0] la_out_read_ptr;  // SW read pointer for out_fifo_mem

   reg [IN_FIFO_WORD_WIDTH-1:0]  read_word_in;
   reg [OUT_FIFO_WORD_WIDTH-1:0] read_word_out;

   reg [31:0] la_in_word_out_0, la_in_word_out_1, la_in_word_out_2;
   reg [31:0] la_out_word_out_0, la_out_word_out_1, la_out_word_out_2;

   //------------------------- Local assignments -------------------------------

   assign in_rdy        = !in_fifo_nearly_full;
   assign matcher_en    = in_pkt_body;
   assign matcher_ce    = (!in_fifo_empty && out_rdy);
   assign matcher_reset = (reset || ids_cmd[0] || end_of_pkt);

   //------------------------- Modules-------------------------------

   fallthrough_small_fifo #(
      .WIDTH(CTRL_WIDTH + DATA_WIDTH),
      .MAX_DEPTH_BITS(2)
   ) input_fifo (
      .din           ({in_ctrl, in_data}),
      .wr_en         (in_wr),
      .rd_en         (in_fifo_rd_en),
      .dout          ({in_fifo_ctrl, in_fifo_data}),
      .full          (),
      .nearly_full   (in_fifo_nearly_full),
      .empty         (in_fifo_empty),
      .reset         (reset),
      .clk           (clk)
   );

   detect7B matcher (
      .ce       (matcher_ce),
      .match_en (matcher_en),
      .clk      (clk),
      .pipe1    ({in_ctrl, in_data}),
      .hwregA   ({pattern_high, pattern_low}),
      .match    (matcher_match),
      .mrst     (matcher_reset)
   );

   dropfifo drop_fifo (
      .clk         (clk),
      .drop_pkt    (matcher_match && end_of_pkt),
      .fiforead    (out_rdy),
      .fifowrite   (out_wr_int),
      .firstword   (begin_pkt),
      .in_fifo     ({in_fifo_ctrl, in_fifo_data}),
      .lastword    (end_of_pkt),
      .rst         (reset),
      .out_fifo    ({out_ctrl, out_data}),
      .valid_data  (out_wr)
   );

   generic_regs #(
      .UDP_REG_SRC_WIDTH (UDP_REG_SRC_WIDTH),
      .TAG               (`IDS_BLOCK_ADDR),      // custom block tag
      .REG_ADDR_WIDTH    (`IDS_REG_ADDR_WIDTH),
      .NUM_COUNTERS      (0),
      .NUM_SOFTWARE_REGS (5),
      .NUM_HARDWARE_REGS (7)
   ) module_regs (
      .reg_req_in       (reg_req_in),
      .reg_ack_in       (reg_ack_in),
      .reg_rd_wr_L_in   (reg_rd_wr_L_in),
      .reg_addr_in      (reg_addr_in),
      .reg_data_in      (reg_data_in),
      .reg_src_in       (reg_src_in),

      .reg_req_out      (reg_req_out),
      .reg_ack_out      (reg_ack_out),
      .reg_rd_wr_L_out  (reg_rd_wr_L_out),
      .reg_addr_out     (reg_addr_out),
      .reg_data_out     (reg_data_out),
      .reg_src_out      (reg_src_out),

      // counters
      .counter_updates  (),
      .counter_decrement(),

      // Software registers
      .software_regs ({
         pattern_high, 
         pattern_low,  
         ids_cmd,      
         la_out_read_ptr,
         la_in_read_ptr  
      }),

      // Hardware registers
      .hardware_regs ({
         matches,
         la_out_word_out_2,
         la_out_word_out_1,
         la_out_word_out_0,
         la_in_word_out_2, 
         la_in_word_out_1, 
         la_in_word_out_0  
      }),

      .clk              (clk),
      .reset            (reset)
   );

   //------------------------------------------------------------
   // FSM
   //------------------------------------------------------------

   always @(*) begin
      out_wr_int = 0;
      if (!in_fifo_empty) begin
         out_wr_int = 1;         // writing to drop_fifo
      end
   end

   always @(*) begin
      in_fifo_rd_en = 0;
      if (!in_fifo_empty && out_rdy) begin
         in_fifo_rd_en = 1;      // reading from input_fifo
      end
   end

   always @(*) begin
      state_next          = state;
      matches_next        = matches;
      header_counter_next = header_counter;
      end_of_pkt_next     = end_of_pkt;
      in_pkt_body_next    = in_pkt_body;
      begin_pkt_next      = begin_pkt;

      case(state)
         START: begin
            if (in_fifo_ctrl != 0) begin
               state_next       = HEADER;
               begin_pkt_next   = 1;
               end_of_pkt_next  = 0; 
            end
         end

         HEADER: begin
            begin_pkt_next = 0;
            if (in_fifo_ctrl == 0) begin
               header_counter_next = header_counter + 1'b1;
               if (header_counter_next == 3) begin
                  state_next = PAYLOAD;
               end
            end
         end

         PAYLOAD: begin
            if (in_fifo_ctrl != 0) begin
               state_next          = START;
               header_counter_next = 0;
               if (matcher_match) begin
                  matches_next = matches + 1;
               end
               end_of_pkt_next  = 1;
               in_pkt_body_next = 0;
            end
            else begin
               in_pkt_body_next = 1;
            end
         end
      endcase
   end

   always @(posedge clk) begin
      if (reset) begin
         matches        <= 0;
         header_counter <= 0;
         state          <= START;
         begin_pkt      <= 0;
         end_of_pkt     <= 0;
         in_pkt_body    <= 0;
      end
      else begin
         if (ids_cmd[0]) 
            matches <= 0;
         else 
            matches <= matches_next;

         header_counter <= header_counter_next;
         state          <= state_next;
         begin_pkt      <= begin_pkt_next;
         end_of_pkt     <= end_of_pkt_next;
         in_pkt_body    <= in_pkt_body_next;
      end
   end

   //------------------------------------------------------------
   // Capture logic for In-FIFO data
   // Write to in_fifo_mem (72 bits) whenever out_wr_int == 1
   //------------------------------------------------------------
   always @(posedge clk) begin
      if (reset) begin
         in_fifo_w_ptr <= 0;
      end
      else if (out_wr_int) begin
         // Save in_fifo_ctrl + in_fifo_data (72 bits)
         in_fifo_mem[in_fifo_w_ptr] <= {in_fifo_ctrl, in_fifo_data};

         // Saturate pointer
         if (in_fifo_w_ptr < CAPTURE_MEM_SIZE - 1)
            in_fifo_w_ptr <= in_fifo_w_ptr + 1;
      end
   end

   //------------------------------------------------------------
   // Capture logic for Out-FIFO data
   // Write to out_fifo_mem (72 bits) whenever out_wr == 1
   //------------------------------------------------------------
   always @(posedge clk) begin
      if (reset) begin
         out_fifo_w_ptr <= 0;
      end
      else if (out_wr) begin
         // Save out_ctrl + out_data (72 bits)
         out_fifo_mem[out_fifo_w_ptr] <= {out_ctrl, out_data};

         // Saturate pointer
         if (out_fifo_w_ptr < CAPTURE_MEM_SIZE - 1)
            out_fifo_w_ptr <= out_fifo_w_ptr + 1;
      end
   end

   //------------------------------------------------------------
   // Read from in_fifo_mem based on la_in_read_ptr
   // Split 72 bits = 3 x 32-bit outputs
   //------------------------------------------------------------
   always @(posedge clk) begin
      if (reset) begin
         la_in_word_out_0 <= 0;
         la_in_word_out_1 <= 0;
         la_in_word_out_2 <= 0;
      end
      else begin
         read_word_in = in_fifo_mem[ la_in_read_ptr[CAPTURE_ADDR_WIDTH-1:0] ];

         la_in_word_out_0 <= read_word_in[31:0];
         la_in_word_out_1 <= read_word_in[63:32];
         la_in_word_out_2 <= {24'b0, read_word_in[71:64]}; 
      end
   end

   //------------------------------------------------------------
   // Read from out_fifo_mem based on la_out_read_ptr
   // Split 72 bits = 3 x 32-bit outputs
   //------------------------------------------------------------
   always @(posedge clk) begin
      if (reset) begin
         la_out_word_out_0 <= 0;
         la_out_word_out_1 <= 0;
         la_out_word_out_2 <= 0;
      end
      else begin
         read_word_out = out_fifo_mem[ la_out_read_ptr[CAPTURE_ADDR_WIDTH-1:0] ];

         la_out_word_out_0 <= read_word_out[31:0];
         la_out_word_out_1 <= read_word_out[63:32];
         la_out_word_out_2 <= {24'b0, read_word_out[71:64]};
      end
   end

endmodule
