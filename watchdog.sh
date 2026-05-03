#!/bin/bash
set -euo pipefail

ACTIVITY_FILE="/workspace/.last_request"
TIMEOUT=900  # 15 minutes in seconds
CHECK_INTERVAL=60

touch "$ACTIVITY_FILE"
echo "==> Watchdog started (idle timeout: ${TIMEOUT}s)"

while true; do
    sleep "$CHECK_INTERVAL"

    LAST=$(stat -c %Y "$ACTIVITY_FILE" 2>/dev/null || date +%s)
    NOW=$(date +%s)
    AGE=$((NOW - LAST))

    if [ "$AGE" -ge "$TIMEOUT" ]; then
        echo "==> No requests in ${AGE}s — shutting down to save costs..."
        kill 1
    fi
done
