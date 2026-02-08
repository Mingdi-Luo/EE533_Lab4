#!/bin/bash
# ------------------------------------------------------------
# Step 5: NIC mode TCP baseline
# Remote logging + local parsing + remote cleanup
# Measure all directed single-flow TCP throughput (n0-n3)
# ------------------------------------------------------------

PASS="rjRXnExEzpK7"
USER="node1"
TIME=5

HOSTS=("nf7.usc.edu" "nf8.usc.edu" "nf9.usc.edu" "nf5.usc.edu")
IPS=("10.0.4.3" "10.0.5.3" "10.0.6.3" "10.0.7.3")
NAMES=("n0" "n1" "n2" "n3")

# 安全端口段
PORTS=(5150 5151 5152 5153)

RESULT="tcp_nic_summary.log"
LOCAL_LOG_DIR="./tcp_nic_logs"

mkdir -p "$LOCAL_LOG_DIR"

# ------------------------------------------------------------
# Cleanup function (will be called on exit)
# ------------------------------------------------------------
cleanup_iperf() {
  echo
  echo "[*] Cleaning up iperf servers and releasing ports..."
  for H in "${HOSTS[@]}"; do
    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
      "$USER@$H" "pkill -u $USER iperf 2>/dev/null"
  done
  echo "[*] iperf cleanup done."
}

# 保证：脚本正常结束 / Ctrl+C / 出错 都会清理端口
trap cleanup_iperf EXIT

# ------------------------------------------------------------
# Header
# ------------------------------------------------------------
echo "--- Step 5 TCP NIC Baseline ($(date)) ---" > "$RESULT"
printf "%-4s %-4s %-12s %-12s\n" "SRC" "DST" "Transfer" "Bandwidth" >> "$RESULT"
echo "----------------------------------------" >> "$RESULT"

# ------------------------------------------------------------
# Initial cleanup (avoid leftover iperf)
# ------------------------------------------------------------
echo "[*] Initial iperf cleanup on all nodes..."
cleanup_iperf

# ------------------------------------------------------------
# Start iperf servers
# ------------------------------------------------------------
echo "[*] Starting TCP servers on all nodes (ports: ${PORTS[*]})..."
for i in 0 1 2 3; do
  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
    "$USER@${HOSTS[$i]}" \
    "iperf -s -p ${PORTS[$i]} > /dev/null 2>&1 &"
done

sleep 1

# ------------------------------------------------------------
# Run directed TCP tests
# ------------------------------------------------------------
echo "[*] Running all directed single-flow TCP tests..."
for SRC in 0 1 2 3; do
  for DST in 0 1 2 3; do
    [ "$SRC" -eq "$DST" ] && continue

    SRC_NAME=${NAMES[$SRC]}
    DST_NAME=${NAMES[$DST]}
    SRC_HOST=${HOSTS[$SRC]}
    DST_IP=${IPS[$DST]}
    DST_PORT=${PORTS[$DST]}
    REMOTE_LOG="/tmp/iperf_tcp_${SRC_NAME}_to_${DST_NAME}.log"

    echo "  [TEST] ${SRC_NAME} -> ${DST_NAME} (port $DST_PORT)"

    sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
      "$USER@$SRC_HOST" \
      "iperf -c $DST_IP -p $DST_PORT -t $TIME > $REMOTE_LOG 2>&1"
  done
done

# ------------------------------------------------------------
# Fetch logs
# ------------------------------------------------------------
echo "[*] Fetching remote logs to $LOCAL_LOG_DIR..."
for i in 0 1 2 3; do
  SRC_NAME=${NAMES[$i]}
  SRC_HOST=${HOSTS[$i]}

  sshpass -p "$PASS" scp -o StrictHostKeyChecking=no \
    "$USER@$SRC_HOST:/tmp/iperf_tcp_${SRC_NAME}_to_*.log" \
    "$LOCAL_LOG_DIR/" 2>/dev/null
done

# ------------------------------------------------------------
# Parse logs
# ------------------------------------------------------------
echo "[*] Parsing logs and generating summary..."
for SRC in 0 1 2 3; do
  for DST in 0 1 2 3; do
    [ "$SRC" -eq "$DST" ] && continue

    SRC_NAME=${NAMES[$SRC]}
    DST_NAME=${NAMES[$DST]}
    FILE="$LOCAL_LOG_DIR/iperf_tcp_${SRC_NAME}_to_${DST_NAME}.log"

    if [ ! -f "$FILE" ]; then
      TRANS="N/A"
      BW="N/A"
    else
      LINE=$(grep -E 'sec.*bits/sec' "$FILE" | tail -n 1)
      if [ -z "$LINE" ]; then
        TRANS="N/A"
        BW="N/A"
      else
        TRANS=$(echo "$LINE" | grep -oE '[0-9.]+ [KMG]Bytes'    | head -1)
        BW=$(echo   "$LINE" | grep -oE '[0-9.]+ [KMG]bits/sec' | head -1)
      fi
    fi

    printf "%-4s %-4s %-12s %-12s\n" \
      "$SRC_NAME" "$DST_NAME" "$TRANS" "$BW" >> "$RESULT"
  done
done

# ------------------------------------------------------------
# Final output
# ------------------------------------------------------------
echo
echo "=== Final TCP NIC Summary ==="
cat "$RESULT"

# ------------------------------------------------------------
# Remove remote logs
# ------------------------------------------------------------
echo
echo "[*] Cleaning remote log files..."
for i in 0 1 2 3; do
  SRC_NAME=${NAMES[$i]}
  SRC_HOST=${HOSTS[$i]}

  sshpass -p "$PASS" ssh -o StrictHostKeyChecking=no \
    "$USER@$SRC_HOST" \
    "rm -f /tmp/iperf_tcp_${SRC_NAME}_to_*.log"
done

echo "[*] Done. Ports will be released automatically."

