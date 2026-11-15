#!/usr/bin/env bash
# ==============================================================================
# Script: hardening.sh
# Purpose: Enterprise Linux VPS Security Hardening Checklist
# Requirements: Run as root or with sudo
# ==============================================================================
set -euo pipefail

echo "=================================================="
echo "🛡️ Starting Production VPS Security Hardening"
echo "=================================================="

# Check root privilege
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ This script must be run as root or via sudo."
  exit 1
fi

echo "1. 🔄 Updating package indices and installing essential tools..."
apt-get update -y
apt-get install -y ufw fail2ban curl git unattended-upgrades ca-certificates

echo "2. 🧱 Configuring UFW (Uncomplicated Firewall)..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH Port'
ufw allow 80/tcp comment 'HTTP Traefik / Cloudflare'
ufw allow 443/tcp comment 'HTTPS Traefik / Cloudflare'
ufw --force enable
ufw status verbose

echo "3. 🔐 Hardening SSH Daemon..."
SSH_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSH_CONFIG" ]; then
  cp "$SSH_CONFIG" "${SSH_CONFIG}.bak.$(date +%F)"
  sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSH_CONFIG"
  sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
  sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' "$SSH_CONFIG"
  sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 4/' "$SSH_CONFIG"
  systemctl restart sshd || systemctl restart ssh
  echo "✅ SSH configuration hardened (Password Auth disabled, Root Login prohibited without key)."
fi

echo "4. 🛡️ Configuring Fail2ban for brute-force protection..."
cat << 'EOF' > /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port    = 22
logpath = %(sshd_log)s
backend = %(default_backend)s
EOF
systemctl enable fail2ban
systemctl restart fail2ban

echo "5. 🐳 Verifying Docker & Traefik permissions..."
mkdir -p ./traefik
touch ./traefik/acme.json
chmod 600 ./traefik/acme.json
echo "✅ Traefik acme.json permissions set to 600 (required by Let's Encrypt)."

echo "6. 🔄 Enabling unattended security upgrades..."
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "=================================================="
echo "🎉 VPS Hardening Checklist successfully applied!"
echo "=================================================="
