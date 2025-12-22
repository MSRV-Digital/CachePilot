#!/usr/bin/env bash
#
# CachePilot - Git Setup Script
#
# Handles Git-based installation and branch management
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

GIT_REPO="https://github.com/MSRV-Digital/CachePilot.git"
INSTALL_DIR="/opt/cachepilot"

select_branch() {
    echo ""
    echo "Available branches:"
    echo "  1) main    - Stable releases (recommended for production)"
    echo "  2) develop - Beta versions (latest features, may be unstable)"
    echo ""
    read -p "Select branch [1]: " choice
    
    case $choice in
        2)
            echo "develop"
            ;;
        *)
            echo "main"
            ;;
    esac
}

install_via_git() {
    local branch="${1:-}"
    
    if [ -z "$branch" ]; then
        branch=$(select_branch)
    fi
    
    echo ""
    echo -e "${BLUE}Installing CachePilot from Git...${NC}"
    echo "Repository: $GIT_REPO"
    echo "Branch: $branch"
    echo "Target: $INSTALL_DIR"
    echo ""
    
    # Backup existing installation
    if [ -d "$INSTALL_DIR" ]; then
        local backup_dir="$INSTALL_DIR.backup-$(date +%Y%m%d_%H%M%S)"
        echo -e "${YELLOW}⚠${NC} Existing installation found, creating backup..."
        mv "$INSTALL_DIR" "$backup_dir"
        echo -e "${GREEN}✓${NC} Backup created: $backup_dir"
        echo ""
    fi
    
    # Clone repository
    if git clone -b "$branch" "$GIT_REPO" "$INSTALL_DIR" 2>&1; then
        echo -e "${GREEN}✓${NC} Repository cloned successfully"
    else
        echo -e "${RED}✗${NC} Failed to clone repository"
        
        # Restore backup if clone failed
        if [ -n "${backup_dir:-}" ] && [ -d "$backup_dir" ]; then
            mv "$backup_dir" "$INSTALL_DIR"
            echo -e "${YELLOW}⚠${NC} Restored from backup"
        fi
        exit 1
    fi
    
    # Set up Git hooks
    setup_git_hooks
    
    # Store branch info
    echo "$branch" > "$INSTALL_DIR/.cachepilot-branch"
    
    echo -e "${GREEN}✓${NC} Git-based installation completed"
}

setup_git_hooks() {
    local hooks_dir="$INSTALL_DIR/.git/hooks"
    
    # Post-merge hook (runs after git pull)
    cat > "$hooks_dir/post-merge" << 'EOFHOOK'
#!/usr/bin/env bash
#
# Post-merge hook - Auto-update after git pull
#

echo "Git merge detected, updating dependencies..."

# Update Python dependencies if requirements changed
if [ -f "api/requirements.txt" ]; then
    if [ -d "api/venv" ]; then
        source api/venv/bin/activate
        pip install -r api/requirements.txt --quiet 2>/dev/null || true
        deactivate
    fi
fi

# Restart API service if running
if systemctl is-active --quiet cachepilot-api.service 2>/dev/null; then
    echo "Restarting API service..."
    systemctl restart cachepilot-api.service 2>/dev/null || true
fi

# Rebuild frontend if package.json changed
if [ -f "frontend/package.json" ] && [ -d "frontend/node_modules" ]; then
    if git diff-tree -r --name-only --no-commit-id ORIG_HEAD HEAD | grep -q "frontend/package.json"; then
        echo "Frontend dependencies changed, consider rebuilding..."
    fi
fi

echo "Post-merge tasks completed"
EOFHOOK

    chmod +x "$hooks_dir/post-merge"
    echo -e "${GREEN}✓${NC} Git hooks configured"
}

convert_to_git() {
    # Convert existing installation to Git-based
    
    echo ""
    echo -e "${YELLOW}Converting existing installation to Git-based management...${NC}"
    echo ""
    
    if [ ! -d "$INSTALL_DIR" ]; then
        echo -e "${RED}✗${NC} Installation directory not found: $INSTALL_DIR"
        exit 1
    fi
    
    cd "$INSTALL_DIR"
    
    # Check if already Git-based
    if [ -d ".git" ]; then
        echo -e "${YELLOW}⚠${NC} Already using Git, checking remote..."
        local current_remote=$(git remote get-url origin 2>/dev/null || echo "")
        
        if [ "$current_remote" = "$GIT_REPO" ]; then
            echo -e "${GREEN}✓${NC} Already connected to correct repository"
            return 0
        else
            echo "Current remote: $current_remote"
            echo "Expected remote: $GIT_REPO"
            read -p "Update remote URL? [y/N]: " update_remote
            if [[ "$update_remote" =~ ^[Yy]$ ]]; then
                git remote set-url origin "$GIT_REPO"
                echo -e "${GREEN}✓${NC} Remote updated"
            fi
            return 0
        fi
    fi
    
    # Initialize Git
    echo "Initializing Git repository..."
    git init
    
    # Add remote
    git remote add origin "$GIT_REPO"
    
    # Fetch remote
    echo "Fetching from remote..."
    git fetch origin
    
    # Determine branch
    local branch="main"
    if [ -f ".cachepilot-branch" ]; then
        branch=$(cat .cachepilot-branch)
    fi
    
    # Create backup of local changes
    echo "Creating backup of local files..."
    local backup_dir="/tmp/cachepilot-local-backup-$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup important local files
    [ -d "api/venv" ] && cp -r api/venv "$backup_dir/" 2>/dev/null || true
    [ -f ".env" ] && cp .env "$backup_dir/" 2>/dev/null || true
    
    # Reset to remote branch
    echo "Synchronizing with remote branch: $branch"
    git reset --hard "origin/$branch"
    
    # Restore local files
    [ -d "$backup_dir/venv" ] && cp -r "$backup_dir/venv" api/ 2>/dev/null || true
    [ -f "$backup_dir/.env" ] && cp "$backup_dir/.env" . 2>/dev/null || true
    
    # Set up hooks
    setup_git_hooks
    
    echo -e "${GREEN}✓${NC} Conversion completed"
    echo "Local backup: $backup_dir"
}

show_git_info() {
    if [ ! -d "$INSTALL_DIR/.git" ]; then
        echo "Not a Git-based installation"
        return 1
    fi
    
    cd "$INSTALL_DIR"
    
    echo ""
    echo "=========================================="
    echo "CachePilot Git Information"
    echo "=========================================="
    echo ""
    echo "Branch:         $(git rev-parse --abbrev-ref HEAD)"
    echo "Commit:         $(git rev-parse --short HEAD)"
    echo "Commit Date:    $(git log -1 --format=%cd --date=short)"
    echo "Latest Tag:     $(git describe --tags --abbrev=0 2>/dev/null || echo 'none')"
    echo "Remote:         $(git remote get-url origin 2>/dev/null || echo 'none')"
    echo ""
    
    # Check for local changes
    local changes=$(git status --short | wc -l)
    if [ "$changes" -gt 0 ]; then
        echo -e "${YELLOW}⚠${NC} Local changes: $changes file(s) modified"
        echo ""
        git status --short | head -10
    else
        echo -e "${GREEN}✓${NC} No local changes"
    fi
    
    echo ""
    
    # Check for available updates
    git fetch origin -q 2>/dev/null || true
    local current=$(git rev-parse HEAD)
    local remote=$(git rev-parse "origin/$(git rev-parse --abbrev-ref HEAD)" 2>/dev/null || echo "")
    
    if [ -n "$remote" ] && [ "$current" != "$remote" ]; then
        echo -e "${BLUE}Updates available:${NC}"
        echo ""
        git log --oneline HEAD..origin/$(git rev-parse --abbrev-ref HEAD) | head -5
        echo ""
        echo "Run 'cachepilot system update' to update"
    else
        echo -e "${GREEN}✓${NC} System is up to date"
    fi
    
    echo ""
}

case "${1:-}" in
    install)
        install_via_git "${2:-}"
        ;;
    convert)
        convert_to_git
        ;;
    info)
        show_git_info
        ;;
    setup-hooks)
        setup_git_hooks
        ;;
    *)
        echo "Usage: $0 {install|convert|info|setup-hooks} [branch]"
        exit 1
        ;;
esac
