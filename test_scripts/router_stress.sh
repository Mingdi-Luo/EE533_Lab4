#!/bin/bash
# ------------------------------------------------------------
# Step 6 (Router mode): UDP small-packet stress test
#
# Scenario:
#   - n0..n3 connected through the NetFPGA IP router
#   - Assumes router bitfile is loaded and routing is configured
#
# Test characteristics:
#   - Full node-pair coverage (n0..n3) via 3 perfect matchings
#   - 4 concurrent UDP flows per round
#   - 1 Gbit/s per flow, 512-byte UDP payload
#
# Logging methodology:
#   - Each UDP client writes its log on the source node (/tmp)
#   - Logs are fetched back to the local machine
#   - Results are parsed locally into a summary file
#   - Remote logs and iperf servers are cleaned up at the end
# ------------------------------------------------------------

PASS="rjRXnExEzpK7"
USER="node1"

# Hostnames, IPs, and logical node names
HOSTS=("nf7.usc.edu" "nf8.usc.edu" "nf9.usc.edu" "nf5.usc.edu")
IPS=("10.0.4.3" "10.0.5.3" "10.0.6.3" "10.0.7.3")
NAMES=("n0" "n1" "n2" "n3")

# Fixed UDP ports for each node (avoid default iperf ports)
PORTS=(5160 5161 5162 5163)

# UDP test parameters
BW="1G"          # Offered bandwidth per flow
PKT=512          # UDP payload size (bytes)
TIME=30          # Test duration (seconds)

# Three rounds of perfect matchings (directed flows)
ROUNDS=(
  "0 1  1 0  2 3  3 2"
  "0 2  2 0  1 3  3 1"
  "0 3  3 0  1 2  2 1"
)

# Output files
MASTER_SUMMARY="udp_router_summary.log"
LOCAL_LOG_DIR="./udp_router_logs"

mkdir -p "$LOCAL_LOG_DIR"

# ------------------------------------------------------------
# Cleanup function
#   - Kill iperf processes owned by this user
#   - Remove remote UDP log files
# ------------------------------------------------------------
cleanup_iperf() {
  echo
  echo "[*] Cleaning up iperf servers and remote UDP logs (router mode)..."
  for H in "${HOSTS[@]}"; do
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
      "$USER@$H" \
      "pkill -u $USER iperf 2>/dev/null; rm -f /tmp/udp_router_*.log 2>/dev/null"
  done
  echo "[*] Cleanup completed."
}

# Ensure cleanup is executed on normal exit, Ctrl+C, or error
trap cleanup_iperf EXIT

# ------------------------------------------------------------
# Initialize summary file
# ------------------------------------------------------------
echo "--- Step 6 UDP Router-mode Stress Test ($(date)) ---" > "$MASTER_SUMMARY"
printf "%-5s %-4s %-4s %-10s %-12s %-10s %-12s %-8s\n" \
  "Round" "SRC" "DST" "Transfer" "Bandwidth" "Jitter" "Loss" "Loss%%" >> "$MASTER_SUMMARY"
echo "----------------------------------------------------------------------------" >> "$MASTER_SUMMARY"

# Initial cleanup to avoid leftover iperf servers or logs
echo "[*] Performing initial cleanup (router mode)..."
cleanup_iperf

# ------------------------------------------------------------
# Execute 3 rounds of UDP stress tests (router mode)
# ------------------------------------------------------------
for R in 0 1 2; do
  ROUND_ID=$((R+1))
  PAIRS=(${ROUNDS[$R]})

  echo
  echo "=== UDP Router Round ${ROUND_ID} ==="

  # Start one UDP iperf server on each node with a fixed port
  echo "[*] Starting UDP servers on ports 5160-5163 (router mode)..."
  for i in 0 1 2 3; do
    H=${HOSTS[$i]}
    P=${PORTS[$i]}
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
      "$USER@$H" \
      "pkill -u $USER iperf 2>/dev/null; iperf -u -s -p $P > /dev/null 2>&1 &"
  done
  sleep 2

  # Launch all UDP clients concurrently for this round
  echo "[*] Launching concurrent UDP flows (router mode)..."
  for ((i=0; i<${#PAIRS[@]}; i+=2)); do
    SRC=${PAIRS[$i]}
    DST=${PAIRS[$((i+1))]}

    SRC_NAME=${NAMES[$SRC]}
    DST_NAME=${NAMES[$DST]}
    SRC_HOST=${HOSTS[$SRC]}
    DST_IP=${IPS[$DST]}
    DST_PORT=${PORTS[$DST]}

    REMOTE_LOG="/tmp/udp_router_${SRC_NAME}_to_${DST_NAME}_r${ROUND_ID}.log"

    echo "  [FLOW] ${SRC_NAME} -> ${DST_NAME} (dst_ip=${DST_IP}, dst_port=${DST_PORT})"

    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
      "$USER@$SRC_HOST" \
      "iperf -u -c $DST_IP -p $DST_PORT -b $BW -l $PKT -t $TIME -i $TIME > $REMOTE_LOG 2>&1" &
  done

  echo "[*] Waiting ${TIME}s for Round ${ROUND_ID} to complete..."
  wait
done

# ------------------------------------------------------------
# Fetch all remote UDP logs to the local machine
# ------------------------------------------------------------
echo
echo "[*] Fetching remote UDP logs (router mode) to $LOCAL_LOG_DIR..."
for i in 0 1 2 3; do
  SRC_HOST=${HOSTS[$i]}
  sshpass -p "$PASS" scp -o StrictHostKeyChecking=no \
    "$USER@$SRC_HOST:/tmp/udp_router_*.log" \
    "$LOCAL_LOG_DIR/" 2>/dev/null
done

# ------------------------------------------------------------
# Parse logs locally and generate summary
# ------------------------------------------------------------
echo "[*] Parsing logs and generating router-mode summary..."
for R in 0 1 2; do
  ROUND_ID=$((R+1))
  PAIRS=(${ROUNDS[$R]})

  for ((i=0; i<${#PAIRS[@]}; i+=2)); do
    SRC=${PAIRS[$i]}
    DST=${PAIRS[$((i+1))]}

    SRC_NAME=${NAMES[$SRC]}
    DST_NAME=${NAMES[$DST]}
    FILE="$LOCAL_LOG_DIR/udp_router_${SRC_NAME}_to_${DST_NAME}_r${ROUND_ID}.log"

    if [ ! -f "$FILE" ]; then
      TRANS="N/A"
      BW_R="N/A"
      JIT="N/A"
      LOSS="N/A"
      LOSS_PCT="N/A"
    else
      # Use a tolerant pattern to capture the final UDP summary line
      LINE=$(grep -E '0\.0-.*sec' "$FILE" | grep 'Bytes' | grep 'bits/sec' | tail -n 1)

      if [ -z "$LINE" ]; then
        TRANS="N/A"
        BW_R="N/A"
        JIT="N/A"
        LOSS="N/A"
        LOSS_PCT="N/A"
      else
        TRANS=$(echo "$LINE"    | grep -oE '[0-9.]+ [KMG]Bytes'     | head -1)
        BW_R=$(echo "$LINE"     | grep -oE '[0-9.]+ [KMG]bits/sec' | head -1)
        JIT=$(echo "$LINE"      | grep -oE '[0-9.]+ ms'            | tail -1)
        LOSS=$(echo "$LINE"     | grep -oE '[0-9]+/[0-9]+'         | head -1)
        LOSS_PCT=$(echo "$LINE" | grep -oE '\([0-9.]+%\)'          | head -1)
      fi
    fi

    printf "%-5s %-4s %-4s %-10s %-12s %-10s %-12s %-8s\n" \
      "$ROUND_ID" "$SRC_NAME" "$DST_NAME" \
      "$TRANS" "$BW_R" "$JIT" "$LOSS" "$LOSS_PCT" >> "$MASTER_SUMMARY"
  done
done

# ------------------------------------------------------------
# Final output
# ------------------------------------------------------------
echo
echo "=== Final UDP Router-mode Summary ==="
cat "$MASTER_SUMMARY"

echo
echo "[*] Step 6 Router-mode UDP test completed."
echo "[*] iperf servers and remote logs will be cleaned up automatically."

