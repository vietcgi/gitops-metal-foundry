#!/bin/bash
set -e

# Colocation Bootstrapper Setup Script
# This script installs necessary packages and deploys configuration files.

echo "Starting Colocation Bootstrapper Setup..."

# 1. Install Dependencies
echo "Installing ISC-DHCP, TFTP, and Nginx..."
sudo apt-get update
sudo apt-get install -y isc-dhcp-server tftpd-hpa nginx wget

# 2. Deploy ISC-DHCP Config
echo "Configuring ISC-DHCP..."
sudo cp dhcpd.conf /etc/dhcp/dhcpd.conf
# Ensure the interface is set (User might need to adjust INTERFACESv4 in /etc/default/isc-dhcp-server)
echo "NOTE: Please ensure INTERFACESv4 is set correctly in /etc/default/isc-dhcp-server"
sudo systemctl restart isc-dhcp-server

# 3. Deploy TFTP Config
echo "Configuring TFTP..."
sudo cp tftpd-hpa /etc/default/tftpd-hpa
sudo systemctl restart tftpd-hpa

# 4. Download iPXE Binaries
echo "Downloading iPXE binaries..."
sudo mkdir -p /srv/tftp
cd /srv/tftp
if [ ! -f ipxe.efi ]; then
    sudo wget http://boot.ipxe.org/ipxe.efi
fi
if [ ! -f undionly.kpxe ]; then
    sudo wget http://boot.ipxe.org/undionly.kpxe
fi
cd -

# 5. Deploy Nginx Config and Handoff Script
echo "Configuring Nginx..."
sudo cp nginx.conf /etc/nginx/sites-available/bootstrapper
sudo ln -sf /etc/nginx/sites-available/bootstrapper /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo systemctl restart nginx

echo "Deploying Handoff Script..."
sudo mkdir -p /var/www/html
sudo cp handoff.ipxe /var/www/html/handoff.ipxe

echo "Setup Complete!"
echo "Please verify services are running:"
echo "  systemctl status isc-dhcp-server"
echo "  systemctl status tftpd-hpa"
echo "  systemctl status nginx"
