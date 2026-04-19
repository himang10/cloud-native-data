#!/bin/bash

NAMESPACE="kafka"

helm uninstall mariadb-1 --namespace ${NAMESPACE}
