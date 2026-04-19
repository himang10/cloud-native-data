#!/bin/bash

NAMESPACE="kafka"

helm uninstall postgres-1 --namespace ${NAMESPACE}
