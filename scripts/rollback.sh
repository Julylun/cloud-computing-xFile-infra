#!/usr/bin/env bash
# ==============================================================================
# Script: rollback.sh
# Purpose: Instant rollback to a previous known working image tag
# Usage: ./scripts/rollback.sh <backend|frontend> [rollback-tag]
# ==============================================================================
set -euo pipefail

SERVICE="${1:-backend}"
TAG="${2:-}"
STATE_FILE=".deploy_state"

echo "=================================================="
echo "⏪ [Rollback] Service: ${SERVICE}"
echo "📅 [Time]: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="

if [ -z "$TAG" ]; then
  if [ -f "$STATE_FILE" ]; then
    TAG=$(grep "^PREV_${SERVICE^^}_TAG=" "$STATE_FILE" 2>/dev/null | cut -d'=' -f2 || echo "")
  fi
fi

if [ -z "$TAG" ]; then
  TAG="latest"
  echo "⚠️ Không tìm thấy tag trước đó trong ${STATE_FILE}. Mặc định rollback về: ${TAG}"
else
  echo "🎯 Khôi phục về tag: ${TAG}"
fi

VAR_NAME="${SERVICE^^}_TAG"
if grep -q "^${VAR_NAME}=" .env; then
  sed -i "s|^${VAR_NAME}=.*|${VAR_NAME}=${TAG}|" .env
else
  echo "${VAR_NAME}=${TAG}" >> .env
fi

# Update state file to reflect current rolled-back version
if [ -f "$STATE_FILE" ]; then
  if grep -q "^${VAR_NAME}=" "$STATE_FILE"; then
    sed -i "s|^${VAR_NAME}=.*|${VAR_NAME}=${TAG}|" "$STATE_FILE"
  else
    echo "${VAR_NAME}=${TAG}" >> "$STATE_FILE"
  fi
fi

echo "📥 Pulling rollback image ${SERVICE}:${TAG}..."
docker compose pull "$SERVICE" || true

echo "🔄 Recreating container with rollback version..."
docker compose up -d --no-deps "$SERVICE"

echo "🩺 Verifying container status..."
sleep 5
docker compose ps "$SERVICE"

echo "=================================================="
echo "✅ Rollback completed for ${SERVICE} to tag ${TAG}!"
echo "=================================================="
