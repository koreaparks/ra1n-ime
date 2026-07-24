#!/bin/bash
set -e

# Move to project root (relative to this script)
cd "$(dirname "$0")/.."

echo "==> Cleaning previous build..."
make clean

echo "==> Building ra1nIME.app with ad-hoc signing..."
make CODESIGN_IDENTITY="-"

echo "==> Creating installer package..."
make pkg

echo ""
echo "==> Done! Package ready:"
ls -lh build/ra1nIME.pkg
