#!/bin/bash

####################################################################################################
# Fix Script: Rebuild Monitoring Network (if DNS resolution fails)
# Usage: bash fix-network.sh
####################################################################################################

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo_header() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

echo_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

echo_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

####################################################################################################
# Step 1: Stop all containers
####################################################################################################
echo_header "STEP 1: Stopping containers"

echo_warning "Stopping monitoring stack..."
docker compose -f docker-compose-monitoring.yml down 2>/dev/null || echo "Not running"

echo_warning "Stopping SNMP exporter..."
docker compose -f docker-compose-snmp-exporter.yml down 2>/dev/null || echo "Not running"

sleep 2
echo_success "Containers stopped"

####################################################################################################
# Step 2: Remove network
####################################################################################################
echo_header "STEP 2: Removing monitoring network"

if docker network ls | grep -q "monitoring-network"; then
    docker network rm monitoring-network
    echo_success "Network 'monitoring-network' removed"
else
    echo_warning "Network 'monitoring-network' not found (already removed)"
fi

sleep 1

####################################################################################################
# Step 3: Restart monitoring stack (creates fresh network)
####################################################################################################
echo_header "STEP 3: Starting monitoring stack"

docker compose -f docker-compose-monitoring.yml up -d
echo_success "Monitoring stack started"

# Wait for containers to be ready
sleep 5

####################################################################################################
# Step 4: Verify network created
####################################################################################################
echo_header "STEP 4: Verifying network"

if docker network ls | grep -q "monitoring-network"; then
    echo_success "Network 'monitoring-network' created"
    docker network inspect monitoring-network --format='Driver: {{.Driver}} | Scope: {{.Scope}}'
else
    echo "Error: Network not created"
    exit 1
fi

####################################################################################################
# Step 5: Start SNMP exporter (join existing network)
####################################################################################################
echo_header "STEP 5: Starting SNMP exporter"

docker compose -f docker-compose-snmp-exporter.yml up -d
echo_success "SNMP exporter started"

sleep 3

####################################################################################################
# Step 6: Verify both on same network
####################################################################################################
echo_header "STEP 6: Verifying containers on shared network"

echo "Containers on 'monitoring-network':"
docker network inspect monitoring-network | grep -E '"Name"|"IPv4Address"' | grep -B1 "172\." | head -20

####################################################################################################
# Step 7: Quick test DNS resolution
####################################################################################################
echo_header "STEP 7: Testing DNS resolution"

echo "Testing DNS from prometheus container..."
if docker exec prometheus ping -c 2 snmp-exporter > /dev/null 2>&1; then
    echo_success "DNS resolution working!"
    docker exec prometheus ping -c 2 snmp-exporter | tail -n 2
else
    echo "Error: DNS resolution still failing"
    exit 1
fi

####################################################################################################
# Summary
####################################################################################################
echo_header "COMPLETED"

echo_success "Network rebuilt successfully!"
echo ""
echo "Next steps:"
echo "  1. Run test script: bash test-snmp-debug.sh"
echo "  2. Check Prometheus targets: http://localhost:9990/targets"
echo "  3. Check Grafana: http://localhost:3000"
