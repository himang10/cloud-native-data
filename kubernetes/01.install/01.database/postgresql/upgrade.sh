#!/bin/bash

NAMESPACE="postgres"

helm upgrade postgres-1 bitnami/postgresql \
  --namespace ${NAMESPACE} \
  -f custom-values.yaml

