#!/bin/bash

NAMESPACE="kafka"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

kubectl delete -f "${SCRIPT_DIR}/mongodb-manifests.yaml" --ignore-not-found
kubectl delete pvc -l app=mongodb-1 -n ${NAMESPACE} --ignore-not-found
