#!/bin/bash

NAMESPACE="redis"

helm upgrade redis-1 bitnami/redis \
  --namespace ${NAMESPACE} \
  -f custom-values.yaml

