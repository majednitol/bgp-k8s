#!/bin/bash

set -e


modprobe dummy || echo "Skipping modprobe dummy (may already be loaded or not allowed)"

# Create dummy0 only if it doesn't exist
if ! ip link show dummy0 &>/dev/null; then
  echo "Creating dummy0 interface"
  ip link add dummy0 type dummy
else
  echo "dummy0 already exists, skipping creation"
fi

# List of IPs to assign
ips=(
  "10.0.0.3/16"
  "10.0.0.2/16"
)

for ip in "${ips[@]}"; do
  if ! ip addr show dummy0 | grep -qw "${ip%/*}"; then
    echo "Adding IP $ip to dummy0"
    ip addr add "$ip" dev dummy0
  else
    echo "IP $ip already assigned to dummy0"
  fi
done

# Bring dummy0 up
ip link set dummy0 up

# Start routers
for i in {1..2}; do
  echo "Starting router$i..."
  port=$((50050 + i))
  gobgpd -f "/etc/router$i.conf" \
    --api-hosts 0.0.0.0:$port \
    --log-level debug > "/dev/stdout" 2>&1 &
done

echo "Waiting for all routers to start..."
sleep 20  

# ✅ Inject Static Routes
echo "Injecting static routes..."

# --- Router1 (AS 13335) ---
echo "→ Router1 (AS 65005)"


gobgp -p 50051 global rib add 10.0.0.2/16 bgpsec
gobgp -p 50052 global rib add 10.0.0.2/16 bgpsec



echo "Static route injection complete."
# Live logs
echo "-----------------------------------------"
echo "Routers are running with debug logs:"
echo "-----------------------------------------"
tail -f /dev/stdout
