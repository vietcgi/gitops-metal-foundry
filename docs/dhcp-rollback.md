# DHCP Infrastructure Rollback Guide

This guide explains how to rollback the centralized DHCP changes and restore the previous site-local DHCP configuration.

## When to Rollback

Rollback if you experience:
- Servers unable to get DHCP leases
- PXE boot failures across multiple sites
- Tailscale connectivity issues preventing DHCP access
- Performance degradation (high latency, timeouts)

## Quick Rollback (Emergency)

If you need to restore service immediately:

### 1. Disable Tinkerbell DHCP

```bash
# Edit the Tinkerbell release
kubectl -n tink-system edit helmrelease tinkerbell

# Find the dhcpEnabled line and change to false:
# dhcpEnabled: true  →  dhcpEnabled: false

# Save and exit (Flux will reconcile automatically)
```

### 2. Re-enable Site DHCP Servers

At each site, restart the local DHCP server:

```bash
# Colo (108.181.38.67)
sudo systemctl start isc-dhcp-server
sudo systemctl enable isc-dhcp-server
sudo systemctl status isc-dhcp-server

# Stop DHCP relay if running
sudo systemctl stop isc-dhcp-relay
sudo systemctl disable isc-dhcp-relay
```

### 3. Verify Service Restored

```bash
# Test DHCP lease
sudo dhclient -r eth0
sudo dhclient -v eth0

# Check assigned IP
ip addr show eth0
```

## Full Rollback Procedure

### Step 1: Restore Tinkerbell Configuration

Revert the changes to `release.yaml`:

```bash
cd /Users/kevin/gitops-metal-foundry

# Option A: Git revert
git log --oneline kubernetes/infrastructure/tinkerbell/release.yaml
git revert <commit-hash-of-dhcp-change>
git push

# Option B: Manual edit
# Edit kubernetes/infrastructure/tinkerbell/release.yaml
# Change dhcpEnabled: true → dhcpEnabled: false
git add kubernetes/infrastructure/tinkerbell/release.yaml
git commit -m "Rollback: Disable centralized DHCP"
git push
```

Wait for Flux to reconcile:

```bash
# Force reconciliation
flux reconcile helmrelease tinkerbell -n tink-system

# Verify DHCP is disabled
kubectl -n tink-system get helmrelease tinkerbell -o yaml | grep dhcpEnabled
```

### Step 2: Restore Site DHCP Configurations

#### Colocation (108.181.38.67)

```bash
# SSH to colo DHCP server
ssh user@108.181.38.67

# Restore DHCP server config from backup
sudo cp /etc/dhcp/dhcpd.conf.backup /etc/dhcp/dhcpd.conf

# Restart DHCP server
sudo systemctl start isc-dhcp-server
sudo systemctl enable isc-dhcp-server

# Stop relay
sudo systemctl stop isc-dhcp-relay
sudo systemctl disable isc-dhcp-relay

# Verify
sudo systemctl status isc-dhcp-server
sudo journalctl -u isc-dhcp-server -n 20
```

#### Home Lab

```bash
# If using router DHCP: re-enable in router admin panel
# If using dnsmasq:
sudo cp /etc/dnsmasq.conf.backup /etc/dnsmasq.conf
sudo systemctl restart dnsmasq
sudo systemctl status dnsmasq
```

### Step 3: Restore Hardware CRD IP Addresses

If you removed hardcoded IPs from Hardware CRDs, restore them:

```bash
# Edit each hardware resource
kubectl -n tink-system edit hardware colo-server-01

# Add back the IP configuration:
spec:
  interfaces:
    - dhcp:
        mac: 00:0c:29:73:03:4b
        hostname: colo-server-01
        ip:
          address: 108.181.38.85
          gateway: 108.181.38.65
          netmask: 255.255.255.224
```

Or restore from Git:

```bash
git checkout HEAD~1 -- kubernetes/infrastructure/tinkerbell/hardware.yaml
git commit -m "Rollback: Restore hardcoded IPs in Hardware CRDs"
git push
```

### Step 4: Remove Tailscale Configuration (Optional)

If you added Tailscale subnet router:

```bash
# Remove Tailscale secret
kubectl -n tink-system delete secret tailscale-auth

# If using standalone subnet router deployment
kubectl -n tink-system delete deployment tailscale-subnet-router
```

### Step 5: Verify Rollback

```bash
# Check Tinkerbell DHCP is disabled
kubectl -n tink-system logs -l app.kubernetes.io/name=tinkerbell --tail=50 | grep -i dhcp

# Test PXE boot from a server
# Should get DHCP from local server, not Tinkerbell

# Verify Hardware CRDs have IPs
kubectl -n tink-system get hardware colo-server-01 -o yaml | grep -A5 "ip:"
```

## Partial Rollback (One Site)

If only one site is having issues, rollback just that site:

### Keep Tinkerbell DHCP Enabled

```bash
# Don't disable Tinkerbell DHCP globally
# Just stop the relay at the problematic site
```

### Restore Local DHCP at Problem Site

```bash
# At the site with issues
sudo systemctl stop isc-dhcp-relay
sudo systemctl start isc-dhcp-server
```

### Update Hardware CRDs

Mark hardware at that site to use static IPs instead of DHCP:

```yaml
# In Hardware CRD
spec:
  interfaces:
    - dhcp:
        mac: 00:0c:29:73:03:4b
        ip:
          address: 108.181.38.85  # Restore static IP
          gateway: 108.181.38.65
          netmask: 255.255.255.224
```

## Post-Rollback Verification

### 1. Test DHCP Leases

```bash
# At each site, test DHCP
sudo dhclient -r eth0
sudo dhclient -v eth0
ip addr show eth0
```

### 2. Test PXE Boot

Boot a server from network and verify:
- Gets DHCP lease from local server
- PXE boots successfully
- Tinkerbell workflow runs
- Server provisions correctly

### 3. Monitor Logs

```bash
# Local DHCP server logs
sudo journalctl -u isc-dhcp-server -f

# Tinkerbell logs (should show no DHCP activity)
kubectl -n tink-system logs -l app.kubernetes.io/name=tinkerbell -f | grep -i dhcp
```

## Troubleshooting Rollback Issues

### DHCP Server Won't Start

**Error**: `dhcpd: No subnet declaration for eth0`

**Fix**: Restore complete DHCP config from backup:
```bash
sudo cp /etc/dhcp/dhcpd.conf.backup /etc/dhcp/dhcpd.conf
sudo systemctl restart isc-dhcp-server
```

### Servers Still Trying to Use Tinkerbell DHCP

**Cause**: DHCP relay still running

**Fix**:
```bash
sudo systemctl stop isc-dhcp-relay
sudo systemctl disable isc-dhcp-relay
sudo systemctl status isc-dhcp-relay  # Should be inactive
```

### Hardware CRDs Missing IP Configuration

**Cause**: IPs were removed but not restored

**Fix**: Restore from Git history or manually add:
```bash
kubectl -n tink-system edit hardware <name>
# Add ip.address, ip.gateway, ip.netmask
```

## Prevention

To avoid needing rollback in the future:

1. **Test in Staging**: Test DHCP changes on one server before rolling out
2. **Backup Configs**: Always backup DHCP configs before changes
3. **Monitor**: Set up alerts for DHCP failures
4. **Document**: Keep site-specific DHCP configs documented
5. **Gradual Rollout**: Migrate one site at a time, not all at once

## Contact

If rollback doesn't resolve issues:
1. Check GitHub issues: https://github.com/vietcgi/gitops-metal-foundry/issues
2. Review Tinkerbell logs for errors
3. Verify network connectivity between sites and OCI
4. Check Tailscale status and routes

## Rollback Checklist

- [ ] Disable Tinkerbell DHCP (`dhcpEnabled: false`)
- [ ] Re-enable local DHCP servers at all sites
- [ ] Stop DHCP relay agents
- [ ] Restore Hardware CRD IP addresses
- [ ] Remove Tailscale subnet router (if added)
- [ ] Test DHCP leases at each site
- [ ] Test PXE boot from each site
- [ ] Verify Tinkerbell workflows still work
- [ ] Monitor for 24-48 hours
- [ ] Document lessons learned
