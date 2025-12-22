#!/usr/bin/env bash
#
# CachePilot - Update Check Script
#
# Checks for available updates from Git repository
#
# Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
# Version: 2.1.2-Beta
# License: MIT
#

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/cachepilot"

check_updates() {
    if [ ! -d "$INSTALL_DIR/.git" ]; then
        echo -e "${RED}✗${NC} Not a Git-based installation"
        echo "Run: sudo bash $INSTALL_DIR/install/scripts/git-setup.sh convert"
        return 2
    fi
    
    cd "$INSTALL_DIR"
    
    echo "Checking for updates..."
    
    # Fetch latest changes
    if ! git fetch origin -q 2>/dev/null; then
        echo -e "${RED}✗${NC} Failed to fetch from remote"
        return 1
    fi
    
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    local current_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse "origin/$current_branch" 2>/dev/null || echo "")
    
    if [ -z "$remote_commit" ]; then
        echo -e "${RED}✗${NC} Remote branch not found: origin/$current_branch"
        return 1
    fi
    
    echo ""
    echo "Branch: $current_branch"
    echo "Current: $(git rev-parse --short HEAD) ($(git log -1 --format=%cd --date=short))"
    echo "Remote:  $(git rev-parse --short origin/$current_branch) ($(git log -1 --format=%cd --date=short origin/$current_branch))"
    echo ""
    
    if [ "$current_commit" != "$remote_commit" ]; then
        local commits_behind=$(git rev-list HEAD..origin/$current_branch --count)
        echo -e "${BLUE}✓ Update available!${NC}"
        echo ""
        echo "Changes ($commits_behind commit(s) behind):"
        echo ""
        git log --oneline HEAD..origin/$current_branch | head -10
        echo ""
        echo "To update, run: sudo cachepilot system update"
        echo "            or: sudo bash $INSTALL_DIR/install/upgrade.sh"
        return 0
    else
        echo -e "${GREEN}✓ System is up to date${NC}"
        return 1
    fi
}

check_updates_json() {
    if [ ! -d "$INSTALL_DIR/.git" ]; then
        echo '{"available": false, "error": "not_git_based"}'
        return 2
    fi
    
    cd "$INSTALL_DIR"
    
    git fetch origin -q 2>/dev/null || true
    
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    local current_commit=$(git rev-parse HEAD)
    local remote_commit=$(git rev-parse "origin/$current_branch" 2>/dev/null || echo "")
    
    if [ -z "$remote_commit" ]; then
        echo '{"available": false, "error": "remote_not_found"}'
        return 1
    fi
    
    if [ "$current_commit" != "$remote_commit" ]; then
        local commits_behind=$(git rev-list HEAD..origin/$current_branch --count)
        local latest_commit_msg=$(git log -1 --format=%s origin/$current_branch)
        
        cat << EOFJSON
{
  "available": true,
  "branch": "$current_branch",
  "current_commit": "$(git rev-parse --short HEAD)",
  "remote_commit": "$(git rev-parse --short origin/$current_branch)",
  "commits_behind": $commits_behind,
  "latest_message": "$latest_commit_msg"
}
EOFJSON
        return 0
    else
        cat << EOFJSON
{
  "available": false,
  "branch": "$current_branch",
  "current_commit": "$(git rev-parse --short HEAD)",
  "up_to_date": true
}
EOFJSON
        return 1
    fi
}

case "${1:-check}" in
    check)
        check_updates
        ;;
    json)
        check_updates_json
        ;;
    *)
        echo "Usage: $0 [check|json]"
        exit 1
        ;;
esac
