#!/bin/bash

NAMESPACE="mariadb"

# 현재 리비전 확인
helm history mariadb-1 --namespace ${NAMESPACE}

# 예: 2번 리비전으로 롤백
#helm rollback chroma 2 --namespace chromadb

