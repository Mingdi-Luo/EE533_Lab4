////////////////////////////////////////////////////////////////////////////////
// Copyright (c) 1995-2008 Xilinx, Inc.  All rights reserved.
////////////////////////////////////////////////////////////////////////////////
//   ____  ____ 
//  /   /\/   / 
// /___/  \  /    Vendor: Xilinx 
// \   \   \/     Version : 10.1
//  \   \         Application : sch2verilog
//  /   /         Filename : detect7B.vf
// /___/   /\     Timestamp : 01/30/2026 21:37:35
// \   \  /  \ 
//  \___\/\___\ 
//
//Command: C:\Xilinx\10.1\ISE\bin\nt\unwrapped\sch2verilog.exe -intstyle ise -family virtex2p -w "C:/Documents and Settings/student/Desktop/ids/detect7B.sch" detect7B.vf
//Design Name: detect7B
//Device: virtex2p
//Purpose:
//    This verilog netlist is translated from an ECS schematic.It can be 
//    synthesized and simulated, but it should not be modified. 
//
`timescale 1ns / 1ps

module detect7B(ce, 
                clk, 
                hwregA, 
                match_en, 
                mrst, 
                pipe1, 
                match);

    input ce;
    input clk;
    input [63:0] hwregA;
    input match_en;
    input mrst;
    input [71:0] pipe1;
   output match;
   
   wire [71:0] pipe0;
   wire [111:0] XLXN_8;
   wire XLXN_11;
   wire XLXN_13;
   wire XLXN_22;
   wire match_DUMMY;
   
   assign match = match_DUMMY;
   reg9B XLXI_1 (.ce(ce), 
                 .clk(clk), 
                 .clr(XLXN_22), 
                 .d(pipe1[71:0]), 
                 .q(pipe0[71:0]));
   busmerge XLXI_2 (.da(pipe0[47:0]), 
                    .db(pipe1[63:0]), 
                    .q(XLXN_8[111:0]));
   wordmatch XLXI_3 (.datacomp(hwregA[55:0]), 
                     .datain(XLXN_8[111:0]), 
                     .wildcard(hwregA[62:56]), 
                     .match(XLXN_11));
   FD XLXI_5 (.C(clk), 
              .D(mrst), 
              .Q(XLXN_22));
   defparam XLXI_5.INIT = 1'b0;
   FDCE XLXI_6 (.C(clk), 
                .CE(XLXN_13), 
                .CLR(XLXN_22), 
                .D(XLXN_13), 
                .Q(match_DUMMY));
   defparam XLXI_6.INIT = 1'b0;
   AND3B1 XLXI_7 (.I0(match_DUMMY), 
                  .I1(XLXN_11), 
                  .I2(match_en), 
                  .O(XLXN_13));
endmodule
