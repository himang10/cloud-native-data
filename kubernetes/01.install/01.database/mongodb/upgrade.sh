#!/bin/bash
# mongodb-manifests.yaml 수정 후 적용

NAMESPACE="kafka"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl apply -f "${SCRIPT_DIR}/mongodb-manifests.yaml"

echo ""
echo "MongoDB 업그레이드 완료. 상태 확인:"
kubectl get pods,svc -n ${NAMESPACE} -l app=mongodb-1

