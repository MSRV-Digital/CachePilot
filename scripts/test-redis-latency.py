#!/usr/bin/env python3
"""
CachePilot - Redis Latency Testing Tool

Tests Redis instance latency with various operations (PING, GET, SET)
Measures min/max/avg/p95/p99 latencies for performance validation.

Author: Patrick Schlesinger <cachepilot@msrv-digital.de>
Company: MSRV Digital
Version: 2.2.0
License: MIT
"""

import argparse
import sys
import time
import statistics
from pathlib import Path
from typing import List, Tuple, Dict

try:
    import redis
except ImportError:
    print("Error: redis-py library not installed")
    print("Install: pip3 install redis")
    sys.exit(1)


def load_tenant_config(tenant: str, tenants_dir: str = "/var/cachepilot/tenants") -> Dict:
    """Load tenant configuration from config.env file"""
    config_file = Path(tenants_dir) / tenant / "config.env"
    
    if not config_file.exists():
        raise FileNotFoundError(f"Tenant config not found: {config_file}")
    
    config = {}
    with open(config_file, 'r') as f:
        for line in f:
            line = line.strip()
            if '=' in line and not line.startswith('#'):
                key, value = line.split('=', 1)
                config[key] = value
    
    return config


def test_latency(host: str, port: int, password: str, use_tls: bool, 
                 iterations: int = 100) -> Dict[str, List[float]]:
    """
    Test Redis latency with PING, GET, SET operations
    
    Returns:
        Dictionary with operation names and latency lists (in milliseconds)
    """
    
    # Setup connection parameters
    conn_params = {
        'host': host,
        'port': port,
        'password': password,
        'socket_timeout': 5,
        'socket_connect_timeout': 5,
        'decode_responses': True
    }
    
    if use_tls:
        # TLS connection
        conn_params['ssl'] = True
        conn_params['ssl_cert_reqs'] = 'none'  # Skip cert verification for testing
    
    results = {
        'PING': [],
        'GET': [],
        'SET': []
    }
    
    try:
        # Create Redis connection
        r = redis.Redis(**conn_params)
        
        # Test connection
        r.ping()
        print(f"✓ Connected to Redis at {host}:{port} ({'TLS' if use_tls else 'Plain-Text'})")
        
        # Warmup
        print(f"Running warmup (10 operations)...")
        for _ in range(10):
            r.ping()
        
        print(f"Running latency test ({iterations} iterations per operation)...")
        
        # Test PING
        print("  Testing PING...", end='', flush=True)
        for i in range(iterations):
            start = time.perf_counter()
            r.ping()
            end = time.perf_counter()
            latency_ms = (end - start) * 1000
            results['PING'].append(latency_ms)
        print(" ✓")
        
        # Test GET (key that doesn't exist - fastest case)
        print("  Testing GET...", end='', flush=True)
        test_key = f'test:latency:{int(time.time())}'
        for i in range(iterations):
            start = time.perf_counter()
            r.get(test_key)
            end = time.perf_counter()
            latency_ms = (end - start) * 1000
            results['GET'].append(latency_ms)
        print(" ✓")
        
        # Test SET
        print("  Testing SET...", end='', flush=True)
        test_value = 'latency_test_value'
        for i in range(iterations):
            start = time.perf_counter()
            r.set(f'{test_key}:{i}', test_value)
            end = time.perf_counter()
            latency_ms = (end - start) * 1000
            results['SET'].append(latency_ms)
        print(" ✓")
        
        # Cleanup
        r.delete(*[f'{test_key}:{i}' for i in range(iterations)])
        
    except redis.ConnectionError as e:
        print(f"\n✗ Connection error: {e}")
        sys.exit(1)
    except redis.AuthenticationError as e:
        print(f"\n✗ Authentication error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ Error: {e}")
        sys.exit(1)
    
    return results


def calculate_statistics(latencies: List[float]) -> Dict[str, float]:
    """Calculate min, max, avg, p95, p99 from latency list"""
    if not latencies:
        return {}
    
    sorted_latencies = sorted(latencies)
    n = len(sorted_latencies)
    
    return {
        'min': min(latencies),
        'max': max(latencies),
        'avg': statistics.mean(latencies),
        'p50': sorted_latencies[int(n * 0.50)],
        'p95': sorted_latencies[int(n * 0.95)],
        'p99': sorted_latencies[int(n * 0.99)]
    }


def print_results(results: Dict[str, List[float]]):
    """Print formatted latency test results"""
    print("\n" + "="*70)
    print("Redis Latency Test Results")
    print("="*70)
    print(f"{'Operation':<10} {'Min':>8} {'Avg':>8} {'P50':>8} {'P95':>8} {'P99':>8} {'Max':>8}")
    print("-"*70)
    
    for operation, latencies in results.items():
        if not latencies:
            continue
        
        stats = calculate_statistics(latencies)
        print(f"{operation:<10} "
              f"{stats['min']:>7.2f}ms "
              f"{stats['avg']:>7.2f}ms "
              f"{stats['p50']:>7.2f}ms "
              f"{stats['p95']:>7.2f}ms "
              f"{stats['p99']:>7.2f}ms "
              f"{stats['max']:>7.2f}ms")
    
    print("="*70)
    
    # Overall assessment
    avg_latency = statistics.mean([stats['avg'] for op, lats in results.items() 
                                   if lats and (stats := calculate_statistics(lats))])
    
    print("\nPerformance Assessment:")
    if avg_latency < 5:
        print(f"  ✓ EXCELLENT - Average latency: {avg_latency:.2f}ms (memory-only performance)")
    elif avg_latency < 20:
        print(f"  ✓ GOOD - Average latency: {avg_latency:.2f}ms (acceptable for most use cases)")
    elif avg_latency < 50:
        print(f"  ⚠ FAIR - Average latency: {avg_latency:.2f}ms (consider optimization)")
    elif avg_latency < 100:
        print(f"  ⚠ SLOW - Average latency: {avg_latency:.2f}ms (optimization recommended)")
    else:
        print(f"  ✗ VERY SLOW - Average latency: {avg_latency:.2f}ms (disk I/O bottleneck likely)")
        print("     Recommendation: Switch to memory-only persistence mode")
    print()


def main():
    parser = argparse.ArgumentParser(
        description='Test Redis instance latency',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
  # Test tenant by name (auto-loads config)
  %(prog)s test-tenant
  
  # Test with custom connection
  %(prog)s --host 10.0.0.27 --port 7600 --password <pass>
  
  # Test with TLS
  %(prog)s --host 10.0.0.27 --port 7300 --password <pass> --tls
  
  # More iterations for accurate results
  %(prog)s test-tenant --iterations 1000
        '''
    )
    
    parser.add_argument('tenant', nargs='?', help='Tenant name (loads config automatically)')
    parser.add_argument('--host', help='Redis host (default: from config or 127.0.0.1)')
    parser.add_argument('--port', type=int, help='Redis port (default: from config)')
    parser.add_argument('--password', help='Redis password (default: from config)')
    parser.add_argument('--tls', action='store_true', help='Use TLS connection')
    parser.add_argument('--plain', action='store_true', help='Use plain-text connection (no TLS)')
    parser.add_argument('--iterations', type=int, default=100, 
                       help='Number of test iterations (default: 100)')
    parser.add_argument('--tenants-dir', default='/var/cachepilot/tenants',
                       help='Tenants directory path (default: /var/cachepilot/tenants)')
    
    args = parser.parse_args()
    
    # Determine connection parameters
    host = args.host
    port = args.port
    password = args.password
    use_tls = args.tls
    
    if args.tenant:
        # Load from tenant config
        try:
            config = load_tenant_config(args.tenant, args.tenants_dir)
            
            # Override with config values if not specified
            if not host:
                # Try to get internal_ip from system.yaml, fallback to localhost
                host = '127.0.0.1'
                try:
                    with open('/etc/cachepilot/system.yaml', 'r') as f:
                        for line in f:
                            if 'internal_ip:' in line and not line.strip().startswith('#'):
                                # Extract value, remove any inline comments
                                value = line.split(':', 1)[1].strip()
                                host = value.split('#')[0].strip()
                                break
                except:
                    pass
            
            if not port:
                security_mode = config.get('SECURITY_MODE', 'tls-only')
                if args.plain or security_mode == 'plain-only':
                    port = int(config.get('PORT_PLAIN', config.get('PORT', 7600)))
                    use_tls = False
                else:
                    port = int(config.get('PORT_TLS', config.get('PORT', 7300)))
                    use_tls = True
            
            if not password:
                password = config.get('PASSWORD', '')
            
            print(f"Testing tenant: {args.tenant}")
            print(f"Config loaded from: {args.tenants_dir}/{args.tenant}/config.env")
            
        except FileNotFoundError as e:
            print(f"Error: {e}")
            sys.exit(1)
    
    # Validate required parameters
    if not all([host, port, password]):
        parser.error("Either specify tenant name or provide --host, --port, and --password")
    
    # Override TLS setting if --plain specified
    if args.plain:
        use_tls = False
    
    # Run latency test
    print(f"\nStarting latency test:")
    print(f"  Target: {host}:{port}")
    print(f"  Mode: {'TLS' if use_tls else 'Plain-Text'}")
    print(f"  Iterations: {args.iterations}")
    print()
    
    results = test_latency(host, port, password, use_tls, args.iterations)
    print_results(results)


if __name__ == '__main__':
    main()
