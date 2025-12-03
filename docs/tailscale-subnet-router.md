# Tailscale Subnet Router for DHCP

This configuration enables the Tinkerbell pod to act as a Tailscale subnet router, making the DHCP server accessible from all sites via the Tailscale VPN mesh.

## Architecture

The Tinkerbell pod will advertise itself as a subnet router for:
- Colo network: `108.181.38.0/27`
- Home network: `192.168.1.0/24` (adjust as needed)

This allows DHCP relay agents at each site to forward DHCP requests to the Tinkerbell DHCP server over the Tailscale VPN.

## Prerequisites

1. Tailscale auth key with subnet routing permissions
2. Tailscale ACLs configured to allow DHCP traffic (UDP 67-68)

## Configuration

### 1. Create Tailscale Secret

Create a Kubernetes secret with a Tailscale auth key:

```bash
# Generate auth key at https://login.tailscale.com/admin/settings/keys
# Enable "Reusable" and "Ephemeral" options
# Add tag "tag:subnet-router"

kubectl create secret generic tailscale-auth \
  --from-literal=authkey=tskey-auth-XXXXX \
  -n tink-system
```

### 2. Modify Tinkerbell Deployment

The Tinkerbell Helm chart doesn't natively support Tailscale sidecar, so we'll use a post-renderer patch.

Add to `release.yaml` in the `postRenderers` section:

```yaml
postRenderers:
  - kustomize:
      patches:
        # ... existing patches ...
        
        # Add Tailscale sidecar to Tinkerbell deployment
        - target:
            kind: Deployment
            name: tinkerbell
          patch: |-
            - op: add
              path: /spec/template/spec/containers/-
              value:
                name: tailscale
                image: tailscale/tailscale:latest
                env:
                  - name: TS_AUTHKEY
                    valueFrom:
                      secretKeyRef:
                        name: tailscale-auth
                        key: authkey
                  - name: TS_ROUTES
                    value: "108.181.38.0/27,192.168.1.0/24"
                  - name: TS_EXTRA_ARGS
                    value: "--advertise-tags=tag:subnet-router --accept-routes"
                  - name: TS_STATE_DIR
                    value: /var/lib/tailscale
                  - name: TS_USERSPACE
                    value: "false"
                securityContext:
                  capabilities:
                    add:
                      - NET_ADMIN
                volumeMounts:
                  - name: tailscale-state
                    mountPath: /var/lib/tailscale
            - op: add
              path: /spec/template/spec/volumes/-
              value:
                name: tailscale-state
                emptyDir: {}
```

### 3. Update Tailscale ACLs

In your Tailscale admin console, update ACLs to allow DHCP traffic:

```json
{
  "acls": [
    {
      "action": "accept",
      "src": ["tag:dhcp-relay"],
      "dst": ["tag:subnet-router:67-68"]
    },
    {
      "action": "accept",
      "src": ["*"],
      "dst": ["tag:subnet-router:*"]
    }
  ],
  "tagOwners": {
    "tag:subnet-router": ["autogroup:admin"],
    "tag:dhcp-relay": ["autogroup:admin"]
  }
}
```

### 4. Apply Configuration

```bash
# Apply the updated Tinkerbell release
kubectl apply -f kubernetes/infrastructure/tinkerbell/release.yaml

# Wait for pod to restart
kubectl -n tink-system rollout status deployment/tinkerbell

# Verify Tailscale is connected
kubectl -n tink-system exec deployment/tinkerbell -c tailscale -- tailscale status
```

## Verification

### 1. Check Tailscale Status

```bash
# From the Tinkerbell pod
kubectl -n tink-system exec deployment/tinkerbell -c tailscale -- tailscale status

# Should show subnet routes advertised
kubectl -n tink-system exec deployment/tinkerbell -c tailscale -- tailscale status --json | jq '.Self.AllowedIPs'
```

### 2. Approve Subnet Routes

In Tailscale admin console:
1. Go to **Machines**
2. Find the Tinkerbell machine
3. Click **Edit route settings**
4. Approve the advertised routes: `108.181.38.0/27`, `192.168.1.0/24`

### 3. Test Connectivity

From a site machine with Tailscale:

```bash
# Get Tinkerbell Tailscale IP
tailscale status | grep tinkerbell

# Ping Tinkerbell
ping -c 3 <tinkerbell-tailscale-ip>

# Test DHCP port (should connect, may timeout waiting for response)
nc -u -v <tinkerbell-tailscale-ip> 67
```

## Alternative: Standalone Tailscale Subnet Router

If you prefer not to modify the Tinkerbell deployment, deploy a separate subnet router:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tailscale-subnet-router
  namespace: tink-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tailscale-subnet-router
  template:
    metadata:
      labels:
        app: tailscale-subnet-router
    spec:
      containers:
      - name: tailscale
        image: tailscale/tailscale:latest
        env:
        - name: TS_AUTHKEY
          valueFrom:
            secretKeyRef:
              name: tailscale-auth
              key: authkey
        - name: TS_ROUTES
          value: "108.181.38.0/27,192.168.1.0/24"
        - name: TS_EXTRA_ARGS
          value: "--advertise-tags=tag:subnet-router --accept-routes"
        - name: TS_STATE_DIR
          value: /var/lib/tailscale
        securityContext:
          capabilities:
            add:
            - NET_ADMIN
        volumeMounts:
        - name: tailscale-state
          mountPath: /var/lib/tailscale
      volumes:
      - name: tailscale-state
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: tailscale-subnet-router
  namespace: tink-system
spec:
  type: ClusterIP
  selector:
    app: tailscale-subnet-router
  ports:
  - name: dhcp
    protocol: UDP
    port: 67
    targetPort: 67
```

Then configure DHCP relay to point to this service's Tailscale IP.

## Troubleshooting

### Subnet Routes Not Advertised

**Check**:
```bash
kubectl -n tink-system logs deployment/tinkerbell -c tailscale
```

**Fix**: Ensure `NET_ADMIN` capability is granted and `TS_ROUTES` is set correctly.

### Routes Not Approved

**Check**: Tailscale admin console → Machines → tinkerbell → Route settings

**Fix**: Manually approve the routes.

### DHCP Traffic Not Reaching Tinkerbell

**Check**:
```bash
# On Tinkerbell pod
kubectl -n tink-system exec deployment/tinkerbell -c tinkerbell -- tcpdump -i any port 67 or port 68 -v
```

**Fix**: Verify Tailscale ACLs allow UDP 67-68 traffic.

## Performance Considerations

- **Latency**: DHCP over Tailscale adds ~10-50ms latency depending on network
- **Reliability**: Depends on Tailscale connectivity; consider local DHCP backup
- **Bandwidth**: DHCP traffic is minimal (<1 KB per request)

## Security

- **Tailscale Encryption**: All DHCP traffic is encrypted via WireGuard
- **ACLs**: Restrict DHCP access to tagged machines only
- **Auth Keys**: Use ephemeral, reusable keys with expiration
- **Audit**: Monitor Tailscale logs for unauthorized access

## Next Steps

1. Configure DHCP relay at each site (see `dhcp-relay-setup.md`)
2. Test PXE boot from each site
3. Monitor DHCP performance and reliability
4. Plan failover strategy for Tailscale outages
