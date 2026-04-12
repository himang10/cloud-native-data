#!/usr/bin/env bash

set -euo pipefail

NETWORK_NAME="kafka-net"
DRIVER="bridge"

if docker network inspect "${NETWORK_NAME}" >/dev/null 2>&1; then
  echo "[INFO] Docker network '${NETWORK_NAME}' already exists. Reusing it."
else
  echo "[INFO] Docker network '${NETWORK_NAME}' does not exist. Creating it..."
  docker network create --driver "${DRIVER}" "${NETWORK_NAME}"
  echo "[INFO] Docker network '${NETWORK_NAME}' created successfully."
fi
