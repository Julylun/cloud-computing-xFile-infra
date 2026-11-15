#!/usr/bin/env bash
# ==============================================================================
# Script: setup-runner.sh
# Purpose: Automate GitHub Actions Self-Hosted Runner setup on Linux VPS
# Target Repo: Julylun/cloud-computing-xFile-infra
# Usage: ./scripts/setup-runner.sh <GITHUB_RUNNER_TOKEN> [RUNNER_NAME]
# ==============================================================================
set -euo pipefail

RUNNER_TOKEN="${1:-}"
RUNNER_NAME="${2:-vps-self-hosted-runner}"
RUNNER_VERSION="2.322.0"
REPO_URL="https://github.com/Julylun/cloud-computing-xFile-infra"
RUNNER_DIR="/home/$USER/actions-runner"

if [ -z "$RUNNER_TOKEN" ]; then
  echo "❌ Error: Runner token is required."
  echo "Usage: ./scripts/setup-runner.sh <GITHUB_RUNNER_TOKEN> [RUNNER_NAME]"
  echo "Get your runner registration token from:"
  echo "  https://github.com/Julylun/cloud-computing-xFile-infra/settings/actions/runners/new"
  exit 1
fi

echo "=================================================="
echo "🤖 Setting up GitHub Self-Hosted Runner"
echo "Repo:   ${REPO_URL}"
echo "Name:   ${RUNNER_NAME}"
echo "Dir:    ${RUNNER_DIR}"
echo "=================================================="

# Ensure user is in docker group
if ! groups "$USER" | grep -q "\bdocker\b"; then
  echo "🐳 Adding $USER to docker group..."
  sudo usermod -aG docker "$USER" || true
  echo "⚠️ Note: You may need to restart your shell session if docker permissions don't apply immediately."
fi

mkdir -p "${RUNNER_DIR}"
cd "${RUNNER_DIR}"

# Download runner package if not present
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
  PKG_ARCH="x64"
elif [ "$ARCH" = "aarch64" ]; then
  PKG_ARCH="arm64"
else
  PKG_ARCH="x64"
fi

RUNNER_TAR="actions-runner-linux-${PKG_ARCH}-${RUNNER_VERSION}.tar.gz"

if [ ! -f "$RUNNER_TAR" ]; then
  echo "📥 Downloading GitHub Actions Runner v${RUNNER_VERSION}..."
  curl -o "$RUNNER_TAR" -L "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TAR}"
  tar xzf "./${RUNNER_TAR}"
fi

echo "⚙️ Configuring runner with GitHub..."
./config.sh \
  --url "${REPO_URL}" \
  --token "${RUNNER_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "self-hosted,linux,${PKG_ARCH}" \
  --work "_work" \
  --unattended \
  --replace

echo "🚀 Installing runner as systemd service..."
sudo ./svc.sh stop || true
sudo ./svc.sh uninstall || true
sudo ./svc.sh install "$USER"
sudo ./svc.sh start
sudo ./svc.sh status

echo "=================================================="
echo "🎉 Self-Hosted Runner is active and listening for CD jobs!"
echo "=================================================="
