#!/usr/bin/env bash
# Build + push the shared self-hosted runner image to GHCR.
#
# Prereqs:
#   - A running Docker daemon with buildx (Docker Desktop / colima / native on the NAS).
#   - Logged in to GHCR:  echo "$GHCR_PAT" | docker login ghcr.io -u <github-user> --password-stdin
#     (PAT needs write:packages.)
#
# The runner is X64/linux, so the image target is linux/amd64. On the NAS (native
# amd64) this is fast; on an Apple-Silicon Mac buildx emulates amd64 via qemu (slower).
set -euo pipefail

IMAGE="${IMAGE:-ghcr.io/sanyu/github-runner}"
TAG="${TAG:-2.336.0-noble}"
PLATFORM="${PLATFORM:-linux/amd64}"

cd "$(dirname "$0")"

echo ">> building ${IMAGE}:${TAG} (${PLATFORM}) and pushing to GHCR"
docker buildx build \
  --platform "${PLATFORM}" \
  -t "${IMAGE}:${TAG}" \
  -t "${IMAGE}:latest" \
  --push \
  .

echo ">> done. Point the runner at ${IMAGE}:${TAG} (see README)."
