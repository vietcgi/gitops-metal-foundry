# Tinkerbell Bare Metal Provisioning Setup

This document describes the complete Tinkerbell setup for bare metal provisioning in Metal Foundry.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          OCI Cloud (Oracle)                              │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │                   Control Plane VM (170.9.8.103)                   │  │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌──────────────────┐   │  │
│  │  │    K3s Cluster  │  │   Tinkerbell    │  │  socat gRPC      │   │  │
│  │  │                 │──│   v0.21.1       │──│  Proxy :42113    │   │  │
│  │  │                 │  │ (ClusterIP)     │  │                  │   │  │
│  │  └─────────────────┘  └─────────────────┘  └──────────────────┘   │  │
│  │                                                    │               │  │
│  └────────────────────────────────────────────────────│───────────────┘  │
│                                          Port 42113 (External)          │
└──────────────────────────────────────────────────────│──────────────────┘
                                                       │
                                                       │ gRPC over Internet
                                                       │
┌──────────────────────────────────────────────────────│──────────────────┐
│                     Colocation Data Center                               │
│  ┌───────────────────────────────────────────────────│───────────────┐  │
│  │                 PXE Boot Server (108.181.38.67)    │               │  │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌────────│────────────┐   │  │
│  │  │ DHCP    │  │ TFTP    │  │ HTTP    │  │ HookOS │ PXE Boot   │   │  │
│  │  │ Server  │  │ Server  │  │ :8081   │  │ Images │            │   │  │
│  │  └─────────┘  └─────────┘  └─────────┘  └────────────────────┘   │  │
│  └───────────────────────────────────────────────────────────────────┘  │
│                                     │                                    │
│                                     │ PXE Boot                           │
│                                     ▼                                    │
│  ┌───────────────────────────────────────────────────────────────────┐  │
│  │              Bare Metal Servers                                    │  │
│  │  ┌─────────────────────┐  ┌─────────────────────┐                 │  │
│  │  │ colo-server-01 (VM) │  │ anvil (Dell R610)   │                 │  │
│  │  │ MAC: 00:0c:29:73:.. │  │ MAC: 00:21:9b:a1:.. │                 │  │
│  │  │ IP: 108.181.38.85   │  │ IP: 108.181.38.87   │                 │  │
│  │  └─────────────────────┘  └─────────────────────┘                 │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

## Components

### 1. Tinkerbell Server (OCI)

- **Version**: v0.21.1 (unified architecture)
- **Image**: `ghcr.io/tinkerbell/tinkerbell:v0.21.1-f2610bdd`
- **Service**: Running in Kubernetes namespace `tink-system`
- **ClusterIP Service**: Internal gRPC on port 42113

### 2. Socat Proxies (OCI Control Plane)

Two socat-based TCP proxies forward external traffic to the Tinkerbell ClusterIP:

| Service | Port | Purpose |
|---------|------|---------|
| `tinkerbell-grpc-proxy` | 42113 | tink-agent gRPC communication |
| `smee-http-proxy` | 7171 | iPXE auto.ipxe script serving |

**Security**: Both ports are locked down to the colo /27 subnet (108.181.38.64/27) via:
- OCI Security Lists and NSG rules
- iptables rules on the control plane

**Configuration files**: `/etc/systemd/system/tinkerbell-grpc-proxy.service` and `/etc/systemd/system/smee-http-proxy.service`

### 3. PXE Boot Server (Colo)

Located at `108.181.38.67`:

- **DHCP Server**: ISC DHCP Server
- **TFTP Server**: Serving HookOS kernel/initramfs
- **HTTP Server**: Serving OS images (port 8081)

### 4. HookOS

HookOS is the Tinkerbell in-memory OS that runs on bare metal during provisioning.

**Components**:
- Kernel: `vmlinuz-x86_64`
- Initramfs: `initramfs-x86_64`
- tink-agent: Docker container pulled at boot

## Network Configuration

### Required Ports

| Port | Protocol | Direction | Source | Purpose |
|------|----------|-----------|--------|---------|
| 22 | TCP | Inbound | Any | SSH access |
| 67-68 | UDP | LAN | LAN | DHCP |
| 69 | UDP | LAN | LAN | TFTP |
| 80 | TCP | Inbound | Any | HTTP (Let's Encrypt, ingress) |
| 443 | TCP | Inbound | Any | HTTPS |
| 6443 | TCP | Inbound | Admin | Kubernetes API |
| 7171 | TCP | Inbound | **Colo /27** | **Smee HTTP (iPXE scripts)** |
| 8080 | TCP | Inbound | Any | Tinkerbell HTTP boot |
| 42113 | TCP | Inbound | **Colo /27** | **Tinkerbell gRPC** |
| 41641 | UDP | Inbound | Any | Tailscale/WireGuard |

### OCI Security Rules

Ports 7171 and 42113 must be open in (restricted to 108.181.38.64/27):
1. **Security List** (`terraform/modules/vcn/main.tf`)
2. **Network Security Group** (`terraform/modules/vcn/main.tf`)
3. **iptables rules** (`terraform/modules/compute/cloud-init.yaml`)

## PXE Boot Configuration

### PXELINUX Config

Location: `/srv/tftp/pxelinux.cfg/default` (or MAC-specific file)

```
DEFAULT hookos
PROMPT 0
TIMEOUT 30

LABEL hookos
    KERNEL vmlinuz-x86_64
    INITRD initramfs-x86_64
    APPEND ip=dhcp console=ttyS0,115200 console=tty0 \
           facility=colo \
           tinkerbell_tls=false \
           grpc_authority=tinkerbell.qualityspace.com:42113 \
           syslog_host=108.181.38.67 \
           tink_worker_image=ghcr.io/tinkerbell/tink-agent:v0.21.1-f2610bdd \
           hw_addr=<MAC_ADDRESS> \
           worker_id=<MAC_ADDRESS>
```

### Key Kernel Parameters

| Parameter | Description |
|-----------|-------------|
| `grpc_authority` | Tinkerbell gRPC endpoint (domain:port) |
| `tink_worker_image` | Docker image for tink-agent |
| `tinkerbell_tls` | TLS mode (false for unencrypted gRPC) |
| `hw_addr` / `worker_id` | Hardware identifier (MAC address) |
| `syslog_host` | Syslog server for HookOS logs |

## Tinkerbell v0.21.1 Breaking Changes

### API Incompatibility

Tinkerbell v0.21.1 introduced a **unified architecture** with breaking API changes:

- **Old**: `tink-worker` using `GetWorkflowContexts` RPC
- **New**: `tink-agent` using new workflow APIs

### Migration Requirements

1. **Use tink-agent instead of tink-worker**:
   ```
   # Old (broken with v0.21.1)
   tink_worker_image=quay.io/tinkerbell/tink-worker:latest

   # New (works with v0.21.1)
   tink_worker_image=ghcr.io/tinkerbell/tink-agent:v0.21.1-f2610bdd
   ```

2. **Match versions**: The tink-agent version should match the Tinkerbell server version.

## Workflow Templates

### Ubuntu 24.04 Template

Location: `kubernetes/infrastructure/tinkerbell/templates.yaml`

Key workflow actions:
1. `stream-ubuntu-image` - Write OS image to disk
2. `partition-refresh` - Refresh partition table using nsenter
3. `write-netplan` - Configure static network
4. `write-cloud-init-*` - Configure cloud-init for first boot
5. `reboot` - Reboot into installed OS

### Template Variables

Templates use Go templating with variables from Hardware spec:
- `{{.device_1}}` - Worker ID (MAC address)
- `{{.hostname}}` - Target hostname

## Hardware Registration

Hardware specs are registered in Kubernetes:

```yaml
apiVersion: tinkerbell.org/v1alpha1
kind: Hardware
metadata:
  name: colo-server-01
  namespace: tink-system
spec:
  metadata:
    instance:
      hostname: colo-server-01
      id: 00:0c:29:73:03:4b
  interfaces:
    - dhcp:
        mac: 00:0c:29:73:03:4b
        hostname: colo-server-01
```

## Workflow Creation

```yaml
apiVersion: tinkerbell.org/v1alpha1
kind: Workflow
metadata:
  name: colo-server-01-ubuntu
  namespace: tink-system
spec:
  templateRef: ubuntu-2404
  hardwareRef: colo-server-01
  hardwareMap:
    device_1: 00:0c:29:73:03:4b
    hostname: colo-server-01
```

## Troubleshooting

### Check Workflow Status

```bash
kubectl -n tink-system get workflow <name> -o yaml
```

### HookOS SSH Access

SSH into running HookOS (requires SSH key in initramfs):
```bash
ssh root@<IP_ADDRESS>
```

### View tink-agent logs

```bash
# In HookOS
docker logs tink-worker --follow
```

### Common Issues

1. **"unknown method GetWorkflowContexts"**
   - Using old tink-worker with new Tinkerbell
   - Solution: Use tink-agent image

2. **Workflow stuck in PENDING**
   - tink-agent can't connect to gRPC
   - Check: Port 42113 open, socat proxy running

3. **Partition mount failures**
   - Partition table not refreshed after image write
   - Solution: Use nsenter + partprobe in workflow

## Files Reference

| File | Purpose |
|------|---------|
| `terraform/modules/vcn/main.tf` | OCI network security rules |
| `terraform/modules/compute/cloud-init.yaml` | Control plane bootstrap |
| `kubernetes/infrastructure/tinkerbell/templates.yaml` | Workflow templates |
| `/srv/tftp/pxelinux.cfg/` | PXE boot configurations |
