#!/bin/bash

# Clippy Build & Run Script
# Usage: ./run.sh [-d|--debug]

# Parse arguments
DEBUG_MODE=false
for arg in "$@"; do
    if [[ "$arg" == "-d" ]] || [[ "$arg" == "--debug" ]]; then
        DEBUG_MODE=true
        break
    fi
done

# Cleanup function
cleanup() {
    echo "🛑 Shutting down..."
    kill $(jobs -p) 2>/dev/null
    killall -9 Clippy 2>/dev/null
}
trap cleanup EXIT

# Kill existing processes
killall -9 Clippy 2>/dev/null
# Kill existing python sidecar (uvicorn) on port 8000 to prevent conflicts
lsof -t -i:8000 | xargs kill -9 2>/dev/null

echo "🚀 Initializing Clippy Environment..."

# ------------------------------------------------------------------
# 1. Python Sidecar Setup
# ------------------------------------------------------------------
if [ ! -d "sidecar/venv" ]; then
    echo "🐍 Creating Python virtual environment..."
    python3 -m venv sidecar/venv
    source sidecar/venv/bin/activate
    echo "📦 Installing dependencies..."
    pip install -r sidecar/requirements.txt
else
    source sidecar/venv/bin/activate
fi

echo "🧠 Starting Sidecar (Grok/Letta)..."
python3 sidecar/main.py 2>&1 | sed "s/^/[Sidecar] /" &
SIDECAR_PID=$!

# Wait for sidecar to warm up
sleep 2

# ------------------------------------------------------------------
# 2. Swift App Build
# ------------------------------------------------------------------
echo "🔨 Building Clippy..."

# Build
xcodebuild -project Clippy.xcodeproj \
           -scheme Clippy \
           -destination 'platform=macOS,arch=arm64' \
           -configuration Debug \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO \
           -quiet

if [ $? -ne 0 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build succeeded"

# Get app path
BUILD_SETTINGS=$(xcodebuild -project Clippy.xcodeproj -scheme Clippy -showBuildSettings -configuration Debug 2>/dev/null)
TARGET_BUILD_DIR=$(echo "$BUILD_SETTINGS" | grep " TARGET_BUILD_DIR =" | cut -d "=" -f 2 | xargs)
FULL_PRODUCT_NAME=$(echo "$BUILD_SETTINGS" | grep " FULL_PRODUCT_NAME =" | cut -d "=" -f 2 | xargs)
APP_PATH="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"
EXECUTABLE_NAME=$(echo "$BUILD_SETTINGS" | grep " EXECUTABLE_NAME =" | cut -d "=" -f 2 | xargs)

# ------------------------------------------------------------------
# 3. Launch
# ------------------------------------------------------------------
if [ -d "$APP_PATH" ]; then
    if [ "$DEBUG_MODE" = true ]; then
        echo "🐛 Starting in Debug Mode..."
        echo "   Logs from both App and Sidecar will appear below."
        echo "   Press Ctrl+C to stop everything."
        echo ""
        # Run app binary directly to capture stdout/stderr
        "$APP_PATH/Contents/MacOS/$EXECUTABLE_NAME" | sed "s/^/[Clippy]  /"
        
        # Wait for background processes (this is reached if the app closes)
        echo "App exited."
    else
        open "$APP_PATH"
        echo "🚀 App started: $APP_PATH"
        echo "ℹ️  Sidecar is running in the background."
        echo "   Keep this terminal open to maintain the connection."
        echo "   Press Ctrl+C to stop the Sidecar."
        
        # Wait for sidecar (keep script alive)
        wait $SIDECAR_PID
    fi
else
    echo "❌ App not found at $APP_PATH"
    exit 1
fi
