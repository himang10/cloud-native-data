#!/bin/bash

NAMESPACE="mariadb"

helm upgrade mariadb-1 bitnami/mariadb \
  --namespace ${NAMESPACE} \
  -f custom-values.yaml

