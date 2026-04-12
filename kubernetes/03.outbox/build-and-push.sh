#!/bin/bash

# Outbox Pattern 애플리케이션 빌드 및 푸시 스크립트

set -e

REGISTRY="amdp-registry.skala-ai.com/library"
VERSION="1.0.0"

echo "=========================================="
echo "Building and Pushing Outbox Applications"
echo "=========================================="

# Producer 빌드 및 푸시
echo ""
echo "Building Producer..."
cd producer
docker build -t ${REGISTRY}/outbox-producer:${VERSION} .
docker tag ${REGISTRY}/outbox-producer:${VERSION} ${REGISTRY}/outbox-producer:latest

echo "Pushing Producer..."
docker push ${REGISTRY}/outbox-producer:${VERSION}
docker push ${REGISTRY}/outbox-producer:latest

cd ..

# Consumer 빌드 및 푸시
echo ""
echo "Building Consumer..."
cd consumer
docker build -t ${REGISTRY}/outbox-consumer:${VERSION} .
docker tag ${REGISTRY}/outbox-consumer:${VERSION} ${REGISTRY}/outbox-consumer:latest

echo "Pushing Consumer..."
docker push ${REGISTRY}/outbox-consumer:${VERSION}
docker push ${REGISTRY}/outbox-consumer:latest

cd ..

echo ""
echo "=========================================="
echo "Build and Push completed successfully!"
echo "=========================================="
echo ""
echo "Producer image: ${REGISTRY}/outbox-producer:${VERSION}"
echo "Consumer image: ${REGISTRY}/outbox-consumer:${VERSION}"

