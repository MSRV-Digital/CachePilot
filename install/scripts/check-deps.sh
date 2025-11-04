#!/bin/bash
# check-deps.sh - Check and validate all system dependencies

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track missing dependencies
MISSING_DEPS=()
OPTIONAL_MISSING=()

echo "Checking system dependencies..."
echo

# Function to check if command exists
check_command() {
    local cmd=$1
    local required=$2
    local min_version=$3
    
    if command -v "$cmd" &> /dev/null; then
        local version=$(eval "$cmd" --version 2>/dev/null | head -n 1 || echo "unknown")
        echo -e "${GREEN}✓${NC} $cmd found: $version"
        return 0
    else
        if [ "$required" = "true" ]; then
            echo -e "${RED}✗${NC} $cmd not found (required)"
            MISSING_DEPS+=("$cmd")
        else
            echo -e "${YELLOW}⚠${NC} $cmd not found (optional)"
            OPTIONAL_MISSING+=("$cmd")
        fi
        return 1
    fi
}

# Check required dependencies
echo "Required Dependencies:"
check_command "docker" "true" "20.10"
# Check docker compose separately
if docker compose version &> /dev/null; then
    version=$(docker compose version 2>/dev/null | head -n 1 || echo "unknown")
    echo -e "${GREEN}✓${NC} docker compose found: $version"
else
    echo -e "${RED}✗${NC} docker compose not found (required)"
    MISSING_DEPS+=("docker-compose")
fi
check_command "python3" "true" "3.9"
check_command "pip3" "true" ""
check_command "openssl" "true" "1.1"
check_command "nginx" "true" "1.18"
check_command "jq" "true" "1.6"
check_command "systemctl" "true" ""

echo
echo "Optional Dependencies:"
check_command "node" "false" "18" || true
check_command "npm" "false" "9" || true
check_command "yq" "false" "4" || true
check_command "zip" "false" "" || true
check_command "curl" "false" "" || true

echo

# Check Python version
if command -v python3 &> /dev/null; then
    PYTHON_VERSION=$(timeout 3 python3 -c 'import sys; print(".".join(map(str, sys.version_info[:2])))' 2>/dev/null || echo "unknown")
    REQUIRED_VERSION="3.9"
    
    if [ "$PYTHON_VERSION" != "unknown" ]; then
        if [ "$(printf '%s\n' "$REQUIRED_VERSION" "$PYTHON_VERSION" | sort -V | head -n1)" = "$REQUIRED_VERSION" ]; then
            echo -e "${GREEN}✓${NC} Python version $PYTHON_VERSION >= $REQUIRED_VERSION"
        else
            echo -e "${RED}✗${NC} Python version $PYTHON_VERSION < $REQUIRED_VERSION"
            MISSING_DEPS+=("python3>=3.9")
        fi
    fi
fi

# Check Docker daemon
if command -v docker &> /dev/null; then
    if timeout 5 docker ps &> /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Docker daemon is running"
    else
        echo -e "${RED}✗${NC} Docker daemon is not running"
        echo "  Please start Docker: sudo systemctl start docker"
        MISSING_DEPS+=("docker-daemon")
    fi
fi

# Check disk space
AVAILABLE_SPACE=$(timeout 3 df /opt 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
REQUIRED_SPACE=$((1024 * 1024)) # 1GB in KB

if [ "$AVAILABLE_SPACE" -gt "$REQUIRED_SPACE" ]; then
    SPACE_FORMATTED=$(timeout 2 numfmt --to=iec-i --suffix=B $((AVAILABLE_SPACE * 1024)) 2>/dev/null || echo "${AVAILABLE_SPACE}KB")
    echo -e "${GREEN}✓${NC} Sufficient disk space available ($SPACE_FORMATTED)"
else
    SPACE_FORMATTED=$(timeout 2 numfmt --to=iec-i --suffix=B $((AVAILABLE_SPACE * 1024)) 2>/dev/null || echo "${AVAILABLE_SPACE}KB")
    echo -e "${YELLOW}⚠${NC} Low disk space: $SPACE_FORMATTED available"
    echo "  Recommended: 1GB+ free space in /opt"
fi

# Check if running as root or with sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}⚠${NC} Not running as root. Some installation steps may require sudo."
fi

# Check OS compatibility
echo
echo "OS Compatibility Check:"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo "Detected OS: $NAME $VERSION"
    
    # Check for Ubuntu 22.04+ or Debian 12+
    OS_COMPATIBLE=false
    if [ "$ID" = "ubuntu" ]; then
        VERSION_NUM=$(echo "$VERSION_ID" | cut -d. -f1)
        if [ "$VERSION_NUM" -ge 22 ]; then
            echo -e "${GREEN}✓${NC} Ubuntu $VERSION_ID is supported"
            OS_COMPATIBLE=true
        else
            echo -e "${RED}✗${NC} Ubuntu $VERSION_ID is not supported (requires 22.04+)"
        fi
    elif [ "$ID" = "debian" ]; then
        VERSION_NUM=$(echo "$VERSION_ID" | cut -d. -f1)
        if [ "$VERSION_NUM" -ge 12 ]; then
            echo -e "${GREEN}✓${NC} Debian $VERSION_ID is supported"
            OS_COMPATIBLE=true
        else
            echo -e "${RED}✗${NC} Debian $VERSION_ID is not supported (requires 12+)"
        fi
    else
        echo -e "${YELLOW}⚠${NC} $NAME is not officially supported (Ubuntu 22.04+ or Debian 12+ recommended)"
        echo "  Installation may work but is untested on this OS"
    fi
    
    if [ "$OS_COMPATIBLE" = false ] && ([ "$ID" = "ubuntu" ] || [ "$ID" = "debian" ]); then
        MISSING_DEPS+=("compatible-os")
    fi
else
    echo -e "${YELLOW}⚠${NC} Cannot detect OS version"
fi

# Check for existing installations
echo
echo "Existing Installation Check:"
if [ -d "/opt/cachepilot" ]; then
    echo -e "${YELLOW}⚠${NC} Existing installation found at /opt/cachepilot"
    echo "  Backup recommended before proceeding"
else
    echo -e "${GREEN}✓${NC} No existing installation detected"
fi

# Check for port conflicts
echo
echo "Port Availability Check:"
PORTS_TO_CHECK=(80 443 8000)
PORT_CONFLICTS=()

for port in "${PORTS_TO_CHECK[@]}"; do
    if ss -tuln 2>/dev/null | grep -q ":$port " || netstat -tuln 2>/dev/null | grep -q ":$port "; then
        echo -e "${YELLOW}⚠${NC} Port $port is already in use"
        PORT_CONFLICTS+=($port)
    else
        echo -e "${GREEN}✓${NC} Port $port is available"
    fi
done

if [ ${#PORT_CONFLICTS[@]} -gt 0 ]; then
    echo
    echo -e "${YELLOW}Note: Some ports are in use. Installation will proceed but may require configuration:${NC}"
    for port in "${PORT_CONFLICTS[@]}"; do
        case $port in
            80|443) echo "  - Port $port: nginx may conflict with existing web server" ;;
            8000) echo "  - Port 8000: API may need different port configuration" ;;
        esac
    done
fi

# Security checks
echo
echo "Security Pre-flight Checks:"

# Check if SELinux is enabled (informational)
if command -v getenforce &> /dev/null; then
    SELINUX_STATUS=$(getenforce 2>/dev/null || echo "unknown")
    if [ "$SELINUX_STATUS" = "Enforcing" ]; then
        echo -e "${YELLOW}⚠${NC} SELinux is enforcing (may require additional configuration)"
    else
        echo -e "${GREEN}✓${NC} SELinux: $SELINUX_STATUS"
    fi
fi

# Check for AppArmor (informational)
if command -v aa-status &> /dev/null 2>&1; then
    if aa-status --enabled 2>/dev/null; then
        echo -e "${YELLOW}⚠${NC} AppArmor is active (may require additional configuration)"
    fi
fi

# Check kernel version
KERNEL_VERSION=$(uname -r | cut -d. -f1,2)
KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d. -f1)
if [ "$KERNEL_MAJOR" -ge 5 ]; then
    echo -e "${GREEN}✓${NC} Kernel version: $(uname -r) (compatible)"
else
    echo -e "${YELLOW}⚠${NC} Kernel version: $(uname -r) (older than recommended 5.x+)"
fi

# Check system memory
TOTAL_MEM=$(free -m | awk 'NR==2 {print $2}')
REQUIRED_MEM=2048  # 2GB minimum
if [ "$TOTAL_MEM" -ge "$REQUIRED_MEM" ]; then
    echo -e "${GREEN}✓${NC} System memory: ${TOTAL_MEM}MB (sufficient)"
else
    echo -e "${YELLOW}⚠${NC} System memory: ${TOTAL_MEM}MB (recommended: 2GB+)"
fi

# Summary
echo
echo "================================"
if [ ${#MISSING_DEPS[@]} -eq 0 ]; then
    echo -e "${GREEN}All required dependencies satisfied!${NC}"
    if [ ${#OPTIONAL_MISSING[@]} -gt 0 ]; then
        echo
        echo "Optional dependencies missing:"
        for dep in "${OPTIONAL_MISSING[@]}"; do
            echo "  - $dep"
        done
        echo
        echo "You can install these later for additional features:"
        echo "  - node/npm: For frontend development and building"
        echo "  - yq: For advanced YAML parsing in bash scripts"
        echo "  - zip: For handover package creation"
    fi
    exit 0
else
    echo -e "${RED}Missing required dependencies:${NC}"
    for dep in "${MISSING_DEPS[@]}"; do
        echo "  - $dep"
    done
    echo
    echo "Please install missing dependencies and try again."
    echo
    echo "Ubuntu/Debian installation commands:"
    echo "  sudo apt update"
    echo "  sudo apt install -y docker.io docker-compose python3 python3-pip nginx jq"
    echo "  sudo systemctl start docker"
    echo "  sudo systemctl enable docker"
    exit 1
fi
