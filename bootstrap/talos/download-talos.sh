#!/bin/bash
# Download Talos Linux PXE boot files
# Run this on the bootstrapper server (108.181.38.67)

set -e

# Talos version - check https://github.com/siderolabs/talos/releases for latest
TALOS_VERSION="${TALOS_VERSION:-v1.11.5}"
BASE_URL="https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}"
DEST_DIR="/var/www/talos"

echo "Downloading Talos Linux ${TALOS_VERSION} PXE boot files..."

# Create destination directory
sudo mkdir -p "${DEST_DIR}"

# Download kernel
echo "Downloading kernel (vmlinuz)..."
sudo wget -O "${DEST_DIR}/vmlinuz-amd64" \
    "${BASE_URL}/vmlinuz-amd64"

# Download initramfs
echo "Downloading initramfs..."
sudo wget -O "${DEST_DIR}/initramfs-amd64.xz" \
    "${BASE_URL}/initramfs-amd64.xz"

# Copy iPXE script
echo "Copying iPXE boot script..."
sudo cp "$(dirname "$0")/talos.ipxe" "${DEST_DIR}/"

# Set permissions
sudo chown -R www-data:www-data "${DEST_DIR}"
sudo chmod -R 755 "${DEST_DIR}"

echo ""
echo "Files downloaded to ${DEST_DIR}:"
ls -lh "${DEST_DIR}/"

echo ""
echo "==================================================="
echo "NEXT STEPS:"
echo "==================================================="
echo ""
echo "1. Generate Talos machine config (if not already done):"
echo "   talosctl gen config anvil-cluster https://108.181.38.87:6443"
echo ""
echo "2. Copy machine config to web server:"
echo "   sudo cp controlplane.yaml ${DEST_DIR}/"
echo "   # OR for worker node:"
echo "   sudo cp worker.yaml ${DEST_DIR}/"
echo ""
echo "3. Update nginx to serve Talos files on port 8081:"
cat << 'NGINX'

server {
    listen 8081;
    server_name _;

    location /talos/ {
        alias /var/www/talos/;
        autoindex on;
    }
}
NGINX
echo ""
echo "4. PXE boot anvil - it will load Talos and apply the config"
echo ""
