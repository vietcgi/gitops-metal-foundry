#!/bin/bash
#
# DHCP Infrastructure Verification Script
# Tests centralized DHCP setup across all sites
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "DHCP Infrastructure Verification"
echo "========================================="
echo ""

# Test 1: Verify Tinkerbell DHCP is enabled
echo -n "1. Checking Tinkerbell DHCP enabled... "
DHCP_ENABLED=$(kubectl -n tink-system get helmrelease tinkerbell -o jsonpath='{.spec.values.deployment.envs.smee.dhcpEnabled}' 2>/dev/null || echo "false")
if [ "$DHCP_ENABLED" = "true" ]; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC} - DHCP is disabled"
    exit 1
fi

# Test 2: Verify Tinkerbell pod is running
echo -n "2. Checking Tinkerbell pod status... "
POD_STATUS=$(kubectl -n tink-system get pods -l app.kubernetes.io/name=tinkerbell -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [ "$POD_STATUS" = "Running" ]; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC} - Pod status: $POD_STATUS"
    exit 1
fi

# Test 3: Check DHCP logs for activity
echo -n "3. Checking DHCP server logs... "
DHCP_LOGS=$(kubectl -n tink-system logs -l app.kubernetes.io/name=tinkerbell --tail=50 2>/dev/null | grep -i "dhcp" | wc -l)
if [ "$DHCP_LOGS" -gt 0 ]; then
    echo -e "${GREEN}✓ PASS${NC} ($DHCP_LOGS DHCP log entries found)"
else
    echo -e "${YELLOW}⚠ WARNING${NC} - No DHCP logs found (may not have received requests yet)"
fi

# Test 4: Verify Hardware CRDs are registered
echo -n "4. Checking Hardware CRD registrations... "
HARDWARE_COUNT=$(kubectl -n tink-system get hardware --no-headers 2>/dev/null | wc -l)
if [ "$HARDWARE_COUNT" -gt 0 ]; then
    echo -e "${GREEN}✓ PASS${NC} ($HARDWARE_COUNT hardware registered)"
    kubectl -n tink-system get hardware --no-headers | awk '{print "   - " $1}'
else
    echo -e "${RED}✗ FAIL${NC} - No hardware registered"
    exit 1
fi

# Test 5: Verify Hardware CRDs have MAC addresses
echo -n "5. Validating Hardware MAC addresses... "
INVALID_MACS=$(kubectl -n tink-system get hardware -o json 2>/dev/null | jq -r '.items[] | select(.spec.interfaces[0].dhcp.mac == null or .spec.interfaces[0].dhcp.mac == "") | .metadata.name' | wc -l)
if [ "$INVALID_MACS" -eq 0 ]; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${RED}✗ FAIL${NC} - $INVALID_MACS hardware missing MAC addresses"
    exit 1
fi

# Test 6: Check if Tailscale is configured (optional)
echo -n "6. Checking Tailscale configuration... "
TAILSCALE_SECRET=$(kubectl -n tink-system get secret tailscale-auth 2>/dev/null && echo "exists" || echo "missing")
if [ "$TAILSCALE_SECRET" = "exists" ]; then
    echo -e "${GREEN}✓ PASS${NC}"
else
    echo -e "${YELLOW}⚠ WARNING${NC} - Tailscale secret not found (required for remote sites)"
fi

# Test 7: Verify service ports
echo -n "7. Checking Tinkerbell service ports... "
SERVICE_PORTS=$(kubectl -n tink-system get svc tinkerbell -o jsonpath='{.spec.ports[*].port}' 2>/dev/null || echo "")
if echo "$SERVICE_PORTS" | grep -q "42113"; then
    echo -e "${GREEN}✓ PASS${NC} (gRPC port 42113 exposed)"
else
    echo -e "${YELLOW}⚠ WARNING${NC} - gRPC port may not be exposed"
fi

# Test 8: Network connectivity test (if kubectl exec works)
echo -n "8. Testing DHCP port accessibility... "
if kubectl -n tink-system exec -it deployment/tinkerbell -c tinkerbell -- sh -c "exit 0" 2>/dev/null; then
    # Pod is accessible, try to check if DHCP port is listening
    DHCP_LISTENING=$(kubectl -n tink-system exec deployment/tinkerbell -c tinkerbell -- sh -c "netstat -uln 2>/dev/null | grep ':67 ' || ss -uln 2>/dev/null | grep ':67 '" 2>/dev/null || echo "")
    if [ -n "$DHCP_LISTENING" ]; then
        echo -e "${GREEN}✓ PASS${NC} (DHCP port 67 listening)"
    else
        echo -e "${YELLOW}⚠ WARNING${NC} - Cannot verify DHCP port (may need to wait for first request)"
    fi
else
    echo -e "${YELLOW}⚠ SKIP${NC} - Cannot exec into pod"
fi

echo ""
echo "========================================="
echo "Summary"
echo "========================================="
echo ""
echo "Tinkerbell DHCP Status: ${GREEN}ENABLED${NC}"
echo "Hardware Registered: $HARDWARE_COUNT"
echo ""
echo "Next Steps:"
echo "1. Configure DHCP relay at each site (see docs/dhcp-relay-setup.md)"
echo "2. Set up Tailscale subnet routing (see docs/tailscale-subnet-router.md)"
echo "3. Test PXE boot from a registered server"
echo "4. Monitor DHCP logs: kubectl -n tink-system logs -l app.kubernetes.io/name=tinkerbell -f | grep -i dhcp"
echo ""
