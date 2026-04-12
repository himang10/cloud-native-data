#!/bin/bash
# bitnami/mongodb 이미지가 유료화되어 official docker.io/mongo:8.0 이미지 사용

NAMESPACE="kafka"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Namespace가 존재하는지 확인하고 없으면 생성
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo "Namespace $NAMESPACE가 존재하지 않습니다. 생성합니다..."
    kubectl create namespace $NAMESPACE
fi

kubectl apply -f "${SCRIPT_DIR}/mongodb-manifests.yaml"

echo ""
echo "MongoDB 배포 완료. 상태 확인:"
kubectl get pods,svc -n ${NAMESPACE} -l app=mongodb-1
