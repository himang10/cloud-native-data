#!/bin/bash

NAMESPACE="postgres"

helm uninstall postgres-1 --namespace ${NAMESPACE}
