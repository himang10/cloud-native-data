#!/bin/bash

echo " pgvector 확장 활성화 스크립트"

NAMESPACE="postgres"
POD_NAME="postgres-1-postgresql-0"

echo " 1. 모든 데이터베이스에 pgvector 확장 활성화"

# postgres 데이터베이스에 확장 활성화
echo "  - postgres 데이터베이스에 확장 활성화"
kubectl exec -it $POD_NAME -n $NAMESPACE -- psql -U postgres -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"

# cloud 데이터베이스에 확장 활성화  
echo "  - cloud 데이터베이스에 확장 활성화"
kubectl exec -it $POD_NAME -n $NAMESPACE -- psql -U postgres -d cloud -c "CREATE EXTENSION IF NOT EXISTS vector;"

echo " 2. 설치된 확장 확인"
kubectl exec -it $POD_NAME -n $NAMESPACE -- psql -U postgres -d cloud -c "
SELECT 
    d.datname as database, 
    e.extname as extension, 
    e.extversion as version
FROM pg_database d
LEFT JOIN pg_extension e ON true
WHERE d.datname IN ('postgres', 'cloud') AND e.extname = 'vector'
ORDER BY d.datname;
"

echo " 3. pgvector 확장 활성화 완료!"