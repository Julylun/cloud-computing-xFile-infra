#!/usr/bin/env bash
# ==============================================================================
# Script: deploy.sh
# Purpose: Zero-downtime rolling deployment with automatic healthcheck & rollback
# Usage: ./scripts/deploy.sh <backend|frontend|all> [image-tag]
# ==============================================================================
set -euo pipefail

SERVICE="${1:-all}"
TAG="${2:-latest}"
STATE_FILE=".deploy_state"

echo "=================================================="
echo "🚀 [Deploy] Service: ${SERVICE} | Tag: ${TAG}"
echo "📅 [Time]: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=================================================="

# Ensure .env exists
if [ ! -f .env ]; then
  if [ -f .env.example ]; then
    echo "⚠️ .env not found. Creating from .env.example..."
    cp .env.example .env
  else
    echo "❌ Error: .env file missing."
    exit 1
  fi
fi

# Create state file if not existing
touch "${STATE_FILE}"

# Function to update tag in .env & state file
update_env_tag() {
  local svc="$1"
  local new_tag="$2"
  local var_name="${svc^^}_TAG"

  # Find current active tag before overwrite
  local prev_tag
  prev_tag=$(grep "^${var_name}=" "${STATE_FILE}" 2>/dev/null | cut -d'=' -f2 || true)
  if [ -z "$prev_tag" ]; then
    prev_tag=$(grep "^${var_name}=" .env 2>/dev/null | cut -d'=' -f2 || echo "latest")
  fi
  if [ -z "$prev_tag" ]; then
    prev_tag="latest"
  fi

  # Record previous tag in state file for rollback
  if grep -q "^PREV_${var_name}=" "${STATE_FILE}"; then
    sed -i "s|^PREV_${var_name}=.*|PREV_${var_name}=${prev_tag}|" "${STATE_FILE}"
  else
    echo "PREV_${var_name}=${prev_tag}" >> "${STATE_FILE}"
  fi

  # Update or append in .env
  if grep -q "^${var_name}=" .env; then
    sed -i "s|^${var_name}=.*|${var_name}=${new_tag}|" .env
  else
    echo "${var_name}=${new_tag}" >> .env
  fi

  # Record in current state file
  if grep -q "^${var_name}=" "${STATE_FILE}"; then
    sed -i "s|^${var_name}=.*|${var_name}=${new_tag}|" "${STATE_FILE}"
  else
    echo "${var_name}=${new_tag}" >> "${STATE_FILE}"
  fi
}

# Function to check health of deployed service container
verify_health() {
  local svc="$1"
  local container_name="xfile-${svc}"
  local max_attempts=30
  local attempt=1

  echo "🩺 Checking health of ${container_name}..."

  while [ $attempt -le $max_attempts ]; do
    local container_state
    container_state=$(docker inspect --format='{{.State.Status}}' "${container_name}" 2>/dev/null || echo "not_found")

    if [ "$container_state" = "exited" ] || [ "$container_state" = "dead" ]; then
      echo "❌ Container ${container_name} has crashed (status: ${container_state})!"
      echo "📋 Recent container logs:"
      docker logs --tail 20 "${container_name}" 2>&1 || true
      return 1
    fi

    local health_status
    health_status=$(docker inspect --format='{{json .State.Health.Status}}' "${container_name}" 2>/dev/null || echo "not_found")
    health_status=$(echo "${health_status}" | tr -d '"')

    if [ "$health_status" = "healthy" ]; then
      echo "✅ Container ${container_name} is healthy! (attempt ${attempt}/${max_attempts})"
      return 0
    elif [ "$health_status" = "unhealthy" ]; then
      echo "❌ Container ${container_name} reported UNHEALTHY!"
      echo "📋 Recent container logs:"
      docker logs --tail 20 "${container_name}" 2>&1 || true
      return 1
    fi

    echo "⏳ Waiting for healthcheck (${attempt}/${max_attempts}, status: ${health_status}, state: ${container_state})..."
    sleep 2
    attempt=$((attempt + 1))
  done

  echo "❌ Timeout waiting for ${container_name} to become healthy."
  echo "📋 Recent container logs:"
  docker logs --tail 20 "${container_name}" 2>&1 || true
  return 1
}

deploy_single_service() {
  local svc="$1"
  local tag="$2"

  echo "--------------------------------------------------"
  echo "📦 Triển khai: ${svc} (Tag: ${tag})"
  echo "--------------------------------------------------"

  # Save previous tag
  local var_name="${svc^^}_TAG"
  local prev_tag
  prev_tag=$(grep "^${var_name}=" "${STATE_FILE}" 2>/dev/null | cut -d'=' -f2 || true)
  if [ -z "$prev_tag" ]; then
    prev_tag=$(grep "^${var_name}=" .env 2>/dev/null | cut -d'=' -f2 || echo "latest")
  fi
  if [ -z "$prev_tag" ]; then
    prev_tag="latest"
  fi

  update_env_tag "$svc" "$tag"

  echo "📥 Pulling latest image..."
  docker compose pull "$svc" || true

  echo "🔄 Recreating container with zero downtime..."
  docker compose up -d --no-deps "$svc"

  if verify_health "$svc"; then
    echo "🎉 Service ${svc} deployed successfully!"
  else
    echo "🚨 Healthcheck failed for ${svc}! Initiating automatic rollback to: ${prev_tag}"
    ./scripts/rollback.sh "$svc" "$prev_tag"
    exit 1
  fi
}

# Ensure proxy_net network exists
if ! docker network inspect proxy_net >/dev/null 2>&1; then
  echo "🌐 Creating docker network: proxy_net"
  docker network create proxy_net
fi

# Ensure Traefik is running
if [ -z "$(docker compose ps -q traefik 2>/dev/null)" ]; then
  echo "🚦 Starting Traefik Reverse Proxy..."
  # Ensure letsencrypt acme.json has chmod 600 and is not a directory
  mkdir -p ./traefik
  if [ -d ./traefik/acme.json ]; then
    rm -rf ./traefik/acme.json
  fi
  touch ./traefik/acme.json
  chmod 600 ./traefik/acme.json || true
  docker compose up -d traefik
fi

if [ "$SERVICE" = "all" ]; then
  deploy_single_service "backend" "$TAG"
  deploy_single_service "frontend" "$TAG"
else
  deploy_single_service "$SERVICE" "$TAG"
fi

echo "🧹 Cleaning up dangling Docker images..."
docker image prune -f || true

echo "=================================================="
echo "✨ Deployment completed successfully!"
echo "=================================================="
