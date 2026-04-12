#!/bin/bash

echo " pgvector 테스트 시작..."

NAMESPACE="postgres"
POD_NAME="postgres-1-postgresql-0"

# 1. pgvector 확장 설치 확인
echo " 1. pgvector 확장 확인"
kubectl exec -it $POD_NAME -n $NAMESPACE -- psql -U postgres -d cloud -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';"

# 2. 간단한 벡터 테이블 생성 및 데이터 삽입
echo " 2. 벡터 테스트 테이블 생성"
kubectl exec -it $POD_NAME -n $NAMESPACE -- psql -U postgres -d cloud -c "
DROP TABLE IF EXISTS simple_vectors;
CREATE TABLE simple_vectors (id INT, name TEXT, vec VECTOR(3));
INSERT INTO simple_vectors VALUES 
(1, 'A', '[1,2,3]'),
(2, 'B', '[4,5,6]'),
(3, 'C', '[1,1,1]');
"

# 3. 벡터 유사도 검색 테스트
echo " 3. 유사도 검색 테스트"
kubectl exec -it $POD_NAME -n $NAMESPACE -- psql -U postgres -d cloud -c "
SELECT 
    name, 
    vec,
    vec <-> '[2,2,2]' as distance
FROM simple_vectors 
ORDER BY vec <-> '[2,2,2]' 
LIMIT 2;
"

# 4. 벡터 인덱스 생성 테스트
echo " 4. 벡터 인덱스 테스트"
kubectl exec -it $POD_NAME -n $NAMESPACE -- psql -U postgres -d cloud -c "
CREATE INDEX simple_vectors_vec_idx ON simple_vectors USING ivfflat (vec vector_l2_ops) WITH (lists = 1);
SELECT 'Index created successfully' as result;
"

# 5. 정리
echo " 5. 테스트 데이터 정리"
kubectl exec -it $POD_NAME -n $NAMESPACE -- psql -U postgres -d cloud -c "DROP TABLE simple_vectors;"

echo " 5. pgvector 테스트 완료!"