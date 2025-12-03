# DHCP Relay Configuration Guide

This guide explains how to configure DHCP relay at each site (home, colocation) to forward DHCP requests to the centralized Tinkerbell DHCP server running in OCI.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Site Network (Colo: 108.181.38.0/27, Home: 192.168.1.0/24)     │
│                                                                  │
│  ┌────────────┐         ┌─────────────┐                         │
│  │ Bare Metal │  DHCP   │ DHCP Relay  │  Tailscale              │
│  │ Server     │────────▶│ Agent       │─────────────┐           │
│  └────────────┘ Request └─────────────┘             │           │
│                                                      │           │
└──────────────────────────────────────────────────────│───────────┘
                                                       │
                                            Tailscale VPN Mesh
                                                       │
┌──────────────────────────────────────────────────────│───────────┐
│  OCI Control Plane (170.9.8.103)                     │           │
│                                                      │           │
│  ┌─────────────┐         ┌─────────────────────┐    │           │
│  │ Tinkerbell  │  DHCP   │ Smee DHCP Server    │◀───┘           │
│  │ Pod         │◀────────│ (reservation mode)  │                │
│  └─────────────┘ Response└─────────────────────┘                │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **Tailscale installed** at each site with connectivity to OCI control plane
2. **Tinkerbell Tailscale IP** - Find with: `tailscale status | grep tinkerbell`
3. **Hardware CRDs registered** in Tinkerbell for all servers (MAC addresses)

## Option 1: ISC DHCP Relay (Recommended for Colo)

### Installation

```bash
# Ubuntu/Debian
sudo apt-get install isc-dhcp-relay

# RHEL/CentOS
sudo yum install dhcp-relay
```

### Configuration

Edit `/etc/default/isc-dhcp-relay`:

```bash
# Tinkerbell DHCP server IP (via Tailscale)
# Replace with actual Tailscale IP of Tinkerbell pod
SERVERS="100.x.x.x"

# Interfaces to listen on (local network)
INTERFACES="eth0"

# Additional options
OPTIONS=""
```

### Start Service

```bash
sudo systemctl enable isc-dhcp-relay
sudo systemctl start isc-dhcp-relay
sudo systemctl status isc-dhcp-relay
```

### Verify

```bash
# Check relay is forwarding
sudo journalctl -u isc-dhcp-relay -f

# Test DHCP request
sudo dhclient -v eth0
```

## Option 2: dnsmasq DHCP Proxy

If you're already running dnsmasq for DNS, configure it as DHCP proxy:

### Configuration

Edit `/etc/dnsmasq.conf`:

```conf
# Enable DHCP proxy mode
dhcp-range=108.181.38.80,108.181.38.90,255.255.255.224,12h

# Forward DHCP to Tinkerbell (via Tailscale)
dhcp-relay=100.x.x.x

# PXE boot options (optional - Tinkerbell provides these)
dhcp-boot=tag:!ipxe,undionly.kpxe
dhcp-boot=tag:ipxe,https://tinkerbell.qualityspace.com/auto.ipxe

# Interface to listen on
interface=eth0
```

### Restart dnsmasq

```bash
sudo systemctl restart dnsmasq
sudo systemctl status dnsmasq
```

## Option 3: Router-Based DHCP Relay

Many enterprise routers/switches support DHCP relay (RFC 3046).

### Cisco IOS Example

```
interface Vlan100
  description Colo Network
  ip address 108.181.38.65 255.255.255.224
  ip helper-address 100.x.x.x  ! Tinkerbell Tailscale IP
```

### Ubiquiti EdgeRouter Example

```bash
configure
set service dhcp-relay interface eth0
set service dhcp-relay server 100.x.x.x
commit
save
```

### pfSense/OPNsense Example

1. Navigate to **Services → DHCP Relay**
2. Enable DHCP Relay
3. Set **Destination Server**: `100.x.x.x` (Tinkerbell Tailscale IP)
4. Select **Interface**: LAN
5. Save and Apply

## Option 4: Lightweight Container Relay

For sites without dedicated infrastructure, run DHCP relay in a container:

### Docker Compose

Create `docker-compose.yml`:

```yaml
version: '3.8'
services:
  dhcp-relay:
    image: modem7/dhcprelay
    container_name: dhcp-relay
    network_mode: host
    cap_add:
      - NET_ADMIN
    environment:
      - SERVERS=100.x.x.x  # Tinkerbell Tailscale IP
      - INTERFACE=eth0
    restart: unless-stopped
```

Start:

```bash
docker-compose up -d
docker logs -f dhcp-relay
```

## Firewall Configuration

### Allow DHCP Traffic

Ensure firewall allows DHCP relay:

```bash
# iptables
sudo iptables -A INPUT -p udp --dport 67:68 -j ACCEPT
sudo iptables -A OUTPUT -p udp --sport 67:68 -j ACCEPT

# firewalld
sudo firewall-cmd --permanent --add-service=dhcp
sudo firewall-cmd --reload

# ufw
sudo ufw allow 67:68/udp
```

### Tailscale ACLs

Ensure Tailscale ACLs allow DHCP traffic to Tinkerbell:

Edit Tailscale ACL policy:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:dhcp-relay"],
      "dst": ["tag:tinkerbell:67-68"]
    }
  ],
  "tagOwners": {
    "tag:dhcp-relay": ["autogroup:admin"],
    "tag:tinkerbell": ["autogroup:admin"]
  }
}
```

## Testing

### 1. Verify Tailscale Connectivity

```bash
# From relay server, ping Tinkerbell
tailscale ping <tinkerbell-hostname>

# Test DHCP port (should timeout but connection should work)
nc -u -v <tinkerbell-tailscale-ip> 67
```

### 2. Test DHCP Request

```bash
# Release current DHCP lease
sudo dhclient -r eth0

# Request new lease with verbose output
sudo dhclient -v eth0

# Check assigned IP matches Hardware CRD
ip addr show eth0
```

### 3. Monitor DHCP Traffic

```bash
# On relay server
sudo tcpdump -i eth0 port 67 or port 68 -v

# On Tinkerbell pod
kubectl -n tink-system logs -l app=tinkerbell --tail=100 -f | grep -i dhcp
```

### 4. Verify PXE Boot

1. Boot a registered server from network
2. Watch for DHCP DISCOVER/OFFER/REQUEST/ACK in logs
3. Verify iPXE chainloads to Tinkerbell
4. Confirm workflow starts

## Troubleshooting

### DHCP Relay Not Forwarding

**Symptom**: Servers don't get DHCP leases

**Check**:
```bash
# Verify relay is running
sudo systemctl status isc-dhcp-relay

# Check relay logs
sudo journalctl -u isc-dhcp-relay -n 50

# Verify interface is correct
ip link show
```

**Fix**: Ensure `INTERFACES` in relay config matches actual network interface

### Tinkerbell Not Responding

**Symptom**: DHCP requests reach Tinkerbell but no response

**Check**:
```bash
# Verify DHCP is enabled in Tinkerbell
kubectl -n tink-system get helmrelease tinkerbell -o yaml | grep dhcpEnabled

# Check Smee logs
kubectl -n tink-system logs -l app=tinkerbell --tail=100 | grep -i dhcp

# Verify Hardware CRD exists for MAC
kubectl -n tink-system get hardware -o yaml | grep -A5 "mac: 00:0c:29:73:03:4b"
```

**Fix**: Ensure Hardware CRD is registered for the requesting MAC address

### Tailscale Connectivity Issues

**Symptom**: Relay can't reach Tinkerbell via Tailscale

**Check**:
```bash
# Verify Tailscale is running
sudo tailscale status

# Check routes
sudo tailscale status --json | jq '.Peer[] | select(.HostName | contains("tinkerbell"))'

# Test connectivity
ping -c 3 <tinkerbell-tailscale-ip>
```

**Fix**: Ensure Tailscale is connected and subnet routes are advertised

### MAC Not Registered

**Symptom**: "No hardware found for MAC address" in logs

**Check**:
```bash
# List all registered hardware
kubectl -n tink-system get hardware

# Check specific MAC
kubectl -n tink-system get hardware -o yaml | grep -i "00:0c:29:73:03:4b"
```

**Fix**: Register hardware in Tinkerbell:

```yaml
apiVersion: tinkerbell.org/v1alpha1
kind: Hardware
metadata:
  name: my-server
  namespace: tink-system
spec:
  interfaces:
    - dhcp:
        mac: "00:0c:29:73:03:4b"
        hostname: my-server
        ip:
          address: 108.181.38.85
          gateway: 108.181.38.65
          netmask: 255.255.255.224
```

## Migration from Local DHCP

### Step 1: Backup Current Config

```bash
# ISC DHCP
sudo cp /etc/dhcp/dhcpd.conf /etc/dhcp/dhcpd.conf.backup

# dnsmasq
sudo cp /etc/dnsmasq.conf /etc/dnsmasq.conf.backup
```

### Step 2: Run in Parallel (Testing)

Keep local DHCP running on different range while testing relay:

```conf
# Local DHCP: 108.181.38.70-79 (testing)
# Tinkerbell DHCP: 108.181.38.80-90 (production)
```

### Step 3: Monitor Both

```bash
# Watch local DHCP
sudo journalctl -u isc-dhcp-server -f

# Watch relay
sudo journalctl -u isc-dhcp-relay -f

# Watch Tinkerbell
kubectl -n tink-system logs -l app=tinkerbell -f | grep -i dhcp
```

### Step 4: Cutover

Once confident, disable local DHCP:

```bash
sudo systemctl stop isc-dhcp-server
sudo systemctl disable isc-dhcp-server
```

### Step 5: Rollback (If Needed)

```bash
# Re-enable local DHCP
sudo systemctl start isc-dhcp-server
sudo systemctl enable isc-dhcp-server

# Disable relay
sudo systemctl stop isc-dhcp-relay
sudo systemctl disable isc-dhcp-relay
```

## Site-Specific Configuration

### Colocation (108.181.38.0/27)

**Current Setup**: PXE boot server at 108.181.38.67 with ISC DHCP

**Migration**:
1. Install `isc-dhcp-relay` on 108.181.38.67
2. Point to Tinkerbell Tailscale IP
3. Keep existing DHCP server as backup (different range)
4. Test with one server (colo-server-01)
5. Migrate all servers
6. Decommission old DHCP server

### Home Lab (192.168.1.0/24)

**Current Setup**: Router DHCP (assumed)

**Migration**:
1. Check if router supports DHCP relay
2. If yes: Configure relay to Tinkerbell
3. If no: Deploy container-based relay
4. Test with one server
5. Migrate all servers

## Next Steps

After DHCP relay is configured:

1. **Update Hardware CRDs** - Ensure all servers are registered
2. **Test PXE Boot** - Verify end-to-end provisioning
3. **Monitor Performance** - Check DHCP response times over Tailscale
4. **Document Issues** - Track any site-specific problems
5. **Plan Failover** - Consider local DHCP backup for critical sites

## References

- [RFC 3046 - DHCP Relay Agent Information Option](https://www.rfc-editor.org/rfc/rfc3046)
- [ISC DHCP Relay Documentation](https://kb.isc.org/docs/isc-dhcp-44-manual-pages-dhcrelay)
- [Tinkerbell Smee DHCP Modes](https://github.com/tinkerbell/smee)
- [Tailscale Subnet Routing](https://tailscale.com/kb/1019/subnets/)
