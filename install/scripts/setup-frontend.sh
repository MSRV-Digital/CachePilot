#!/bin/bash
#
# CachePilot - Frontend Setup Script
#
# Builds the React frontend application
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Version: 2.1.2-Beta
#

set -e

# Color codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "Setting up CachePilot Frontend..."

# Base directory
BASE_DIR="/opt/cachepilot"
FRONTEND_DIR="$BASE_DIR/frontend"

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo -e "${RED}✗${NC} Node.js not found"
    echo "Please install Node.js 18+ and npm"
    exit 1
fi

if ! command -v npm &> /dev/null; then
    echo -e "${RED}✗${NC} npm not found"
    echo "Please install npm"
    exit 1
fi

echo -e "${GREEN}✓${NC} Node.js $(node --version) found"
echo -e "${GREEN}✓${NC} npm $(npm --version) found"

# Check Node.js version
NODE_VERSION=$(node --version | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    echo -e "${YELLOW}⚠${NC} Node.js version $NODE_VERSION is below recommended 18+"
    read -p "Continue anyway? (y/N): " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Navigate to frontend directory
cd "$FRONTEND_DIR"

# Check if package.json exists
if [ ! -f "package.json" ]; then
    echo -e "${RED}✗${NC} package.json not found in $FRONTEND_DIR"
    exit 1
fi

echo -e "${GREEN}✓${NC} Frontend directory found"

# Install dependencies
echo ""
echo "Installing frontend dependencies..."
echo "(This may take a few minutes)"
npm install

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Dependencies installed"
else
    echo -e "${RED}✗${NC} Failed to install dependencies"
    exit 1
fi

# Build production bundle
echo ""
echo "Building production bundle..."
npm run build

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Frontend built successfully"
else
    echo -e "${RED}✗${NC} Build failed"
    exit 1
fi

# Verify build output
if [ ! -d "$FRONTEND_DIR/dist" ]; then
    echo -e "${RED}✗${NC} Build output not found"
    exit 1
fi

if [ ! -f "$FRONTEND_DIR/dist/index.html" ]; then
    echo -e "${RED}✗${NC} index.html not found in build output"
    exit 1
fi

echo -e "${GREEN}✓${NC} Build output verified"

# Set permissions
chmod -R 755 "$FRONTEND_DIR/dist"
echo -e "${GREEN}✓${NC} Permissions set"

# Show build statistics
echo ""
echo "Build Statistics:"
echo "  Output: $FRONTEND_DIR/dist/"
echo "  Size: $(du -sh $FRONTEND_DIR/dist | cut -f1)"
echo "  Files: $(find $FRONTEND_DIR/dist -type f | wc -l)"

echo ""
echo "========================================"
echo -e "${GREEN}Frontend Build Complete!${NC}"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Run setup-nginx.sh to configure web server"
echo "  2. Visit http://your-server/ to access the frontend"
echo ""
