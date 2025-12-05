#!/bin/bash
# Generate Talos machine configuration for anvil cluster
# This script creates the controlplane.yaml and talosconfig files

set -e

CLUSTER_NAME="anvil-cluster"
CLUSTER_ENDPOINT="https://108.181.38.87:6443"
OUTPUT_DIR="$(dirname "$0")/generated"
TALOS_VERSION="v1.11.5"

# Network configuration for Dell R610
MACHINE_IP="108.181.38.87"
GATEWAY="108.181.38.65"
DNS="8.8.8.8"

echo "Generating Talos configuration for ${CLUSTER_NAME}..."

# Create output directory
mkdir -p "${OUTPUT_DIR}"

# Check if talosctl is installed
if ! command -v talosctl &> /dev/null; then
    echo "Error: talosctl is not installed"
    echo "Install with: curl -sL https://talos.dev/install | sh"
    exit 1
fi

# Generate base configuration
echo "Generating base config with talosctl..."
talosctl gen config "${CLUSTER_NAME}" "${CLUSTER_ENDPOINT}" \
    --output-dir "${OUTPUT_DIR}" \
    --with-docs=false \
    --with-examples=false \
    --install-disk /dev/sda \
    --talos-version "${TALOS_VERSION}"

# Create patch for Dell R610 specific settings
cat > "${OUTPUT_DIR}/anvil-patch.yaml" << 'EOF'
machine:
  network:
    hostname: anvil
    interfaces:
      - interface: eth0
        addresses:
          - 108.181.38.87/27
        routes:
          - network: 0.0.0.0/0
            gateway: 108.181.38.65
    nameservers:
      - 8.8.8.8
      - 1.1.1.1
  install:
    disk: /dev/sda
    bootloader: true
    wipe: true
  kernel:
    modules:
      - name: bnx2
  time:
    servers:
      - time.cloudflare.com
cluster:
  allowSchedulingOnControlPlanes: true
  controllerManager:
    extraArgs:
      bind-address: "0.0.0.0"
  scheduler:
    extraArgs:
      bind-address: "0.0.0.0"
  proxy:
    disabled: false
  # Use Cilium as CNI (disable default Flannel)
  network:
    cni:
      name: none
EOF

# Apply patch to controlplane config
echo "Applying Dell R610 patch..."
talosctl machineconfig patch "${OUTPUT_DIR}/controlplane.yaml" \
    --patch @"${OUTPUT_DIR}/anvil-patch.yaml" \
    --output "${OUTPUT_DIR}/controlplane-anvil.yaml"

echo ""
echo "==================================================="
echo "Configuration generated in ${OUTPUT_DIR}/"
echo "==================================================="
ls -la "${OUTPUT_DIR}/"

echo ""
echo "IMPORTANT FILES:"
echo "  - controlplane-anvil.yaml : Machine config for anvil (patched)"
echo "  - talosconfig             : Client config for talosctl"
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. Copy the machine config to the web server:"
echo "   sudo cp ${OUTPUT_DIR}/controlplane-anvil.yaml /var/www/talos/controlplane.yaml"
echo ""
echo "2. Set up talosctl to manage the cluster:"
echo "   export TALOSCONFIG=${OUTPUT_DIR}/talosconfig"
echo "   talosctl config endpoint 108.181.38.87"
echo "   talosctl config node 108.181.38.87"
echo ""
echo "3. PXE boot the Dell R610 (anvil)"
echo ""
echo "4. After boot, bootstrap the cluster:"
echo "   talosctl bootstrap"
echo ""
echo "5. Get kubeconfig:"
echo "   talosctl kubeconfig ./kubeconfig"
echo ""
echo "6. Install Cilium CNI:"
echo "   cilium install --helm-set ipam.mode=kubernetes"
echo ""
