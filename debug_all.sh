#!/bin/bash

# Cleanup function to kill sidecar when script exits
cleanup() {
    echo "🛑 Shutting down..."
    kill $(jobs -p) 2>/dev/null
}
trap cleanup EXIT

echo "🚀 Initializing Clippy Debug Session..."

# 1. Check/Install Python Dependencies
if [ ! -d "sidecar/venv" ]; then
    echo "🐍 Creating Python virtual environment..."
    python3 -m venv sidecar/venv
    source sidecar/venv/bin/activate
    pip install -r sidecar/requirements.txt
else
    source sidecar/venv/bin/activate
fi

# 2. Start Sidecar in Background (with prefix)
echo "🧠 Starting Sidecar (Grok/Letta)..."
python3 sidecar/main.py 2>&1 | sed "s/^/[Sidecar] /" &
SIDECAR_PID=$!

# Wait for sidecar to warm up
sleep 2

# 3. Build & Run Clippy (with prefix)
echo "📎 Starting Clippy App..."
./run.sh --debug | sed "s/^/[Clippy]  /"

# Wait for background processes
wait $SIDECAR_PID
