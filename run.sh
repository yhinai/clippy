#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🐶 Clippy Build & Run Script${NC}"
echo "=============================="

# 1. Verification
echo -e "\n${GREEN}🔍 Step 1: Verifying Integrity...${NC}"
if [ -f "scripts/verify_integrity.py" ]; then
    python3 scripts/verify_integrity.py
    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ Verification failed!${NC}"
        exit 1
    fi
else
    echo -e "${YELLOW}⚠️  Verification script not found. Skipping.${NC}"
fi

# 2. Build
echo -e "\n${GREEN}🔨 Step 2: Building Clippy...${NC}"

# Build into default DerivedData
xcodebuild -project Clippy.xcodeproj \
           -scheme Clippy            -destination 'platform=macOS' \
           -configuration Debug \
           CODE_SIGN_IDENTITY="" \
           CODE_SIGNING_REQUIRED=NO \
           CODE_SIGNING_ALLOWED=NO

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Build failed!${NC}"
    exit 1
fi

# 3. Run
echo -e "\n${GREEN}🚀 Step 3: Running Clippy...${NC}"

# Locate the built app
BUILD_SETTINGS=$(xcodebuild -project Clippy.xcodeproj -scheme Clippy -showBuildSettings -configuration Debug 2>/dev/null)
TARGET_BUILD_DIR=$(echo "$BUILD_SETTINGS" | grep " TARGET_BUILD_DIR =" | cut -d "=" -f 2 | xargs)
FULL_PRODUCT_NAME=$(echo "$BUILD_SETTINGS" | grep " FULL_PRODUCT_NAME =" | cut -d "=" -f 2 | xargs)
APP_PATH="$TARGET_BUILD_DIR/$FULL_PRODUCT_NAME"

if [ -d "$APP_PATH" ]; then
    echo "Opening $APP_PATH"
    open "$APP_PATH"
else
    echo -e "${RED}❌ App not found at $APP_PATH${NC}"
    # Fallback
    FALLBACK_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "Clippy.app" -type d -path "*/Build/Products/Debug/*" | head -n 1)
    if [ -n "$FALLBACK_PATH" ]; then
        echo "Found at $FALLBACK_PATH"
        open "$FALLBACK_PATH"
    else
        exit 1
    fi
fi

echo -e "${GREEN}✅ Done!${NC}"
