#!/bin/bash

NAMESPACE="redis"

helm uninstall redis-1 --namespace ${NAMESPACE}
