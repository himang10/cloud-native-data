#!/bin/bash

# Helm 저장소 추가
#helm repo add bitnami https://charts.bitnami.com/bitnami
#helm repo update


NAMESPACE="kafka"
#TEST="--dry-run --debug"

# Namespace가 존재하는지 확인하고 없으면 생성
if ! kubectl get namespace $NAMESPACE &> /dev/null; then
    echo "Namespace $NAMESPACE가 존재하지 않습니다. 생성합니다..."
    kubectl create namespace $NAMESPACE
fi

helm upgrade --install postgres-1 bitnami/postgresql \
  --namespace ${NAMESPACE} \
  --version 16.7.4 \
  --set global.security.allowInsecureImages=true \
  -f custom-values.yaml
