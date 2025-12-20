# CachePilot - Network Performance Guide

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>  
Company: MSRV Digital  
Version: 2.1.0-beta  
License: MIT

Copyright (c) 2025 Patrick Schlesinger, MSRV Digital

---

## Overview

CachePilot Redis instances are optimized for high-performance network access. This guide covers the performance optimizations implemented for internal network deployments.

## Redis Performance Settings

All Redis instances are automatically configured with optimized settings for network performance.

### Network Optimizations

```conf
# TCP Performance
tcp-backlog 511              # 4x connection queue (vs. 128 default)
timeout 60                   # Fast dead connection cleanup (vs. 300s)
tcp-keepalive 30             # Frequent keepalive probes (vs. 60s)

# Connection Management
maxclients 10000             # Maximum concurrent connections
client-output-buffer-limit normal 0 0 0
client-output-buffer-limit replica 256mb 64mb 60
client-output-buffer-limit pubsub 32mb 8mb 60

# Multi-Threading (Redis 6.0+)
io-threads 4                 # 4x network throughput
io-threads-do-reads yes

# Monitoring
latency-monitor-threshold 100   # Log operations > 100ms
```

**Impact:**
- 10,000 concurrent connections supported
- 4x network I/O throughput improvement
- Optimized timeouts for faster failure detection
- TCP_NODELAY enabled by default (low latency)

## Installation Configuration

### Network Binding

During installation, CachePilot prompts for the internal IP address. This is critical for network access:

**For network access:**
- Enter your internal server IP (e.g., `10.0.0.5`, `192.168.1.100`)
- Or use `0.0.0.0` to bind to all interfaces

**⚠️ WARNING:** Using `127.0.0.1` restricts Redis to localhost only - not accessible over network!

### System-Level Tuning (Optional)

During installation, you can apply optional system-level optimizations:

```bash
# Applied automatically during installation if selected
# Or run manually:
sudo bash /opt/cachepilot/install/scripts/setup-network-tuning.sh
```

**System optimizations:**
```bash
net.core.somaxconn = 65535              # 512x connection capacity
net.ipv4.tcp_max_syn_backlog = 8192     # Better connection handling
vm.overcommit_memory = 1                # Required for Redis fork()
```

**Plus:**
- Transparent Huge Pages (THP) disabled - eliminates 30-50ms latency spikes
- TCP buffers increased to 16MB
- Optimized TCP timeouts
- Docker daemon configured for performance

### Docker Daemon Optimizations

The system tuning script also configures Docker daemon (`/etc/docker/daemon.json`):

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "mtu": 1500,
  "storage-driver": "overlay2",
  "userland-proxy": false
}
```

**Benefits:**
- `userland-proxy: false` - Uses iptables directly for better network performance
- `mtu: 1500` - Standard MTU for optimal network compatibility
- `overlay2` - Fastest storage driver for Docker
- Log rotation - Prevents disk space issues

## Performance Comparison

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Max Connections (Kernel) | ~128 | 65,535 | 512x |
| TCP Backlog | 128 | 511 | 4x |
| I/O Throughput | 1x | 4x | 4x |
| Timeout Detection | 300s | 60s | 5x faster |
| THP Latency Spikes | 30-50ms | 0ms | Eliminated |

## Verification

### Check Network Configuration
```bash
# View internal IP setting
grep internal_ip /etc/cachepilot/system.yaml

# Should NOT be 127.0.0.1 for network access
```

### Verify System Tuning
```bash
# Check connection capacity
sysctl net.core.somaxconn          # Should be 65535

# Check memory overcommit
sysctl vm.overcommit_memory        # Should be 1

# Check THP status
cat /sys/kernel/mm/transparent_hugepage/enabled   # Should show [never]
```

### Test Redis Performance
```bash
# Install redis-benchmark
apt-get install redis-tools

# Basic throughput test
redis-benchmark -h <ip> -p <port> \
  --tls --cacert /path/to/ca.crt \
  --cert /path/to/redis.crt \
  --key /path/to/redis.key \
  -a <password> \
  -t set,get -n 100000 -c 50 -q
```

## Troubleshooting

### Redis Not Accessible Over Network

**Problem:** Cannot connect to Redis from another machine

**Solution:**
```bash
# 1. Check internal_ip setting
sudo nano /etc/cachepilot/system.yaml
# Must NOT be 127.0.0.1 or localhost

# 2. Restart tenant
cachepilot restart <tenant>

# 3. Check firewall
sudo ufw status
# Ensure Redis port is allowed from internal network
```

### Low Throughput

**Problem:** Slower than expected performance

**Check:**
```bash
# 1. Verify io-threads setting
cat /var/cachepilot/tenants/<tenant>/redis.conf | grep io-threads

# 2. Check system settings
sysctl net.core.somaxconn

# 3. Monitor latency
docker exec redis-<tenant> redis-cli \
  --tls --cacert /certs/ca.crt \
  --cert /certs/redis.crt \
  --key /certs/redis.key \
  -a <password> \
  --latency-history
```

## Updating Existing Installation

If you have an existing installation with `127.0.0.1`:

```bash
# 1. Update configuration
sudo nano /etc/cachepilot/system.yaml
# Change: internal_ip: 127.0.0.1
# To: internal_ip: <your-internal-ip> or 0.0.0.0

# 2. Apply system tuning (optional but recommended)
sudo bash /opt/cachepilot/install/scripts/setup-network-tuning.sh

# 3. Restart all tenants
for tenant in $(cachepilot list --quiet | awk '{print $1}'); do
  cachepilot restart $tenant
done

# 4. Reboot for full effect (optional)
sudo reboot
```

## Best Practices

1. **Network Binding:** Always use internal IP or `0.0.0.0` for production
2. **System Tuning:** Apply system-level optimizations for best performance
3. **Monitoring:** Enable latency monitoring to identify bottlenecks
4. **Testing:** Benchmark performance after deployment
5. **Firewall:** Configure firewall to allow Redis ports from internal network only

## References

- [Redis Latency Optimization](https://redis.io/docs/management/optimization/latency/)
- [Redis I/O Threading](https://redis.io/docs/management/optimization/cpu/)
- [Linux TCP Tuning](https://www.kernel.org/doc/Documentation/networking/ip-sysctl.txt)

---

Last Updated: 2025-12-20 | Version: 2.1.0-beta
