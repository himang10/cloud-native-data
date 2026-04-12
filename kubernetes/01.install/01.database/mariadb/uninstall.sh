#!/bin/bash

NAMESPACE="mariadb"

helm uninstall mariadb-1 --namespace ${NAMESPACE}
