#!/bin/bash

# ==========================================
# Antigravity Swarm Watchdog (V5.6)
# ==========================================
# Role: Automation for DATA_MINER (Gemini CLI)
# ==========================================

# Data Bus Directories
OUTBOX="docs/agent/exchange/outbox"
INBOX="docs/agent/exchange/inbox"
ARCHIVE="docs/agent/exchange/archive"

# Ensure structure
mkdir -p "$OUTBOX" "$INBOX" "$ARCHIVE"

echo "[*] Watchdog V5.6 active. Monitoring: $OUTBOX"
echo "[*] Using: gemini (Headless Mode)"
echo "---------------------------------------------------"

# Bash YAML parser (Concise)
parse_yaml() {
    local key=$1
    local file=$2
    grep -E "^${key}:" "$file" | sed -E "s/^${key}:[[:space:]]*//; s/['\"]//g"
}

# Function to process all files in outbox
process_outbox() {
    for TASK_FILE in "$OUTBOX"/*.yaml; do
        [ -f "$TASK_FILE" ] || continue

        echo "[+] Processing Manifest: $TASK_FILE"

        TASK_ID=$(parse_yaml "task_id" "$TASK_FILE")
        TOOL=$(parse_yaml "target_tool" "$TASK_FILE")

        if [[ "$TOOL" == "JULES" ]]; then
            # Do nothing. Leave the file in outbox for Jules to read directly from repo.
            continue
        fi

        if [[ "$TOOL" == "GEMINI_CLI" ]]; then
            echo "[-] Tool: DATA_MINER. Task ID: $TASK_ID"
            ACTION=$(parse_yaml "action" "$TASK_FILE")
            INPUT_TARGET=$(parse_yaml "input" "$TASK_FILE")
            RULE=$(parse_yaml "compression_rule" "$TASK_FILE")
            PROMPT="Role: DATA_MINER. Goal: $ACTION. Constraints: $RULE. Context: $([ -f "$INPUT_TARGET" ] && tail -n 500 "$INPUT_TARGET" || echo "No file context"). Output: Concise YAML."
            
            echo "[-] Executing Gemini CLI... (Headless)"
            RESULT=$(gemini -p "$PROMPT")

            # Finalize Response in Inbox
            OUT_FILE="$INBOX/result_${TASK_ID}.yaml"
            {
                echo "---"
                echo "task_id: \"$TASK_ID\""
                echo "status: \"success\""
                echo "summary: |"
                echo "$RESULT" | sed 's/^/  /'
            } > "$OUT_FILE"

            echo "[v] Entry processed: $OUT_FILE"
            
            # Cleanup only for GEMINI_CLI
            mv "$TASK_FILE" "$ARCHIVE/"
            echo "[*] Manifest $TASK_ID moved to archive."
            echo "---------------------------------------------------"
        fi
    done
}

# Initial scan
process_outbox

# Main Loop (Monitoring)
while true; do
    # Wait for new manifest
    inotifywait -q -e close_write "$OUTBOX" >/dev/null
    process_outbox
done
