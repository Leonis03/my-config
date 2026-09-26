#!/usr/bin/env bash
# run-intent.sh -- Execute a script inside Honor Linux Lab PRoot container via Intent injection without Root.
# Usage:
#   bash run-intent.sh <script-to-run.sh> [adb-target]
# Example:
#   bash run-intent.sh my_task.sh <device-ip>:<adb-port>

set -euo pipefail

SCRIPT_FILE="${1:-}"
ADB_TARGET="${2:-${ANDROID_SERIAL:-}}"

if [ -z "$SCRIPT_FILE" ] || [ ! -f "$SCRIPT_FILE" ]; then
    echo "Usage: $0 <script-file> [adb-target]" >&2
    exit 1
fi

ADB_CMD="adb"
if [ -n "$ADB_TARGET" ]; then
    ADB_CMD="adb -s $ADB_TARGET"
fi

echo "=== 1. Checking ADB connection ==="
$ADB_CMD get-state >/dev/null 2>&1 || {
    echo "Error: Device not connected via ADB." >&2
    exit 2
}

echo "=== 2. Pushing execution payload to /sdcard ==="
$ADB_CMD push "$SCRIPT_FILE" /sdcard/container_exec.sh
$ADB_CMD shell "chmod 777 /sdcard/container_exec.sh; rm -f /sdcard/container_exec.log"

echo "=== 3. Sending injected Intent to ActivityPcEngine ==="
$ADB_CMD shell 'am start -n com.hihonor.pcengine/com.hihonor.hnpcengineclient.pcengine.ActivityPcEngine \
  -d "content://com.hihonor.filemanager.share.fileprovider/root/dummy\" ; sh /tablet/container_exec.sh ; echo \"StartFinished\" ; echo \"test.deb\""'

echo "=== 4. Waiting for script completion ==="
sleep 2

echo "=== 5. Fetching execution output ==="
$ADB_CMD shell "cat /sdcard/container_exec.log 2>/dev/null || echo 'Note: No log generated or script still running.'"
