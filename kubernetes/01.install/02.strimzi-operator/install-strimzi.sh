#!/bin/bash

set -e

echo "=== Strimzi Kafka Operator 설치 ==="

# Strimzi 버전 설정 (현재 설치 버전: 0.51.0)
# 최신 릴리스: https://github.com/strimzi/strimzi-kafka-operator/releases
STRIMZI_VERSION="0.51.0"

# Namespace 생성 (이미 존재하면 유지)
echo "Kafka 네임스페이스 생성..."
kubectl create namespace kafka --dry-run=client -o yaml | kubectl apply -f -

# Strimzi Operator 설치 (apply: 신규 설치 및 업그레이드 모두 지원)
echo "Strimzi Operator 설치 중 (버전: ${STRIMZI_VERSION})..."
kubectl apply -f "https://strimzi.io/install/latest?namespace=kafka" -n kafka

# Operator Pod가 준비될 때까지 대기
echo "Operator 준비 대기 중..."
kubectl rollout status deployment strimzi-cluster-operator -n kafka --timeout=300s

echo ""
echo "=== Strimzi Operator 설치 완료 (버전: ${STRIMZI_VERSION}) ==="
echo ""
echo "Operator 상태 확인:"
echo "  kubectl get pods -n kafka -l name=strimzi-cluster-operator"
