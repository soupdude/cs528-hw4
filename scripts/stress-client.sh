#!/bin/bash
# Stress-test wrapper for the provided http-client. Runs on each client VM.
#
# The client is silent without -v and exits with a traceback on its first failed
# request. This wrapper runs it (without -v) for a fixed duration, restarts it after
# each failure, and counts failures. A run that reaches the time limit had no errors.
#
# Usage: ./stress-client.sh <client-number> [seconds=180] [timeout=5]
SERVER="${SERVER:-10.128.0.5}"
ID="${1:-1}"
DURATION="${2:-180}"
TIMEOUT="${3:-5}"
LOG="stress_client${ID}_$(date +%H%M%S).log"
now() { TZ=America/New_York date +%H:%M:%S; }

errors=0
end=$((SECONDS + DURATION))
echo "client $ID start $(now) ET  duration=${DURATION}s  timeout=${TIMEOUT}s" | tee "$LOG"

while [ "$SECONDS" -lt "$end" ]; do
  # Different seed per client (and per restart) so clients request different files.
  timeout "$((end - SECONDS))" ./http-client -d "$SERVER" -p 80 -b "" -w 12k-files \
    -n 10000000 -i 11999 -r "$((ID * 1000 + errors))" -t "$TIMEOUT" 2>>"$LOG"
  rc=$?
  [ "$rc" -eq 124 ] && break          # stopped by the time limit: no error
  errors=$((errors + 1))
  echo "client $ID error #$errors at $(now) (exit $rc): $(tail -n 2 "$LOG" | head -n 1)" | tee -a "$LOG"
  sleep 0.5                           # don't spin if the server is refusing everything
done

echo "client $ID end $(now) ET  errors=$errors" | tee -a "$LOG"
