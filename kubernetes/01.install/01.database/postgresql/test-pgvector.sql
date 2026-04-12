-- pgvector 확장 테스트 스크립트
-- 이 스크립트는 PostgreSQL에 연결한 후 실행하여 pgvector 기능을 테스트할 수 있습니다.

-- 1. 확장 설치 확인
SELECT name, default_version, installed_version 
FROM pg_available_extensions 
WHERE name = 'vector';

-- 2. 확장 활성화 확인
SELECT extname, extversion 
FROM pg_extension 
WHERE extname = 'vector';

-- 3. 벡터 설정 확인
SHOW shared_preload_libraries;

-- 4. 테스트 테이블 생성
DROP TABLE IF EXISTS test_vectors;
CREATE TABLE test_vectors (
    id SERIAL PRIMARY KEY,
    name TEXT,
    embedding VECTOR(3)
);

-- 5. 테스트 데이터 삽입
INSERT INTO test_vectors (name, embedding) VALUES
    ('item1', '[1, 2, 3]'),
    ('item2', '[4, 5, 6]'),
    ('item3', '[7, 8, 9]'),
    ('item4', '[1, 1, 1]');

-- 6. 벡터 거리 계산 테스트
SELECT 
    name,
    embedding,
    embedding <-> '[2, 2, 2]' AS l2_distance,
    embedding <#> '[2, 2, 2]' AS negative_inner_product,
    embedding <=> '[2, 2, 2]' AS cosine_distance
FROM test_vectors
ORDER BY embedding <-> '[2, 2, 2]';

-- 7. 인덱스 생성 테스트
CREATE INDEX test_vectors_embedding_idx 
ON test_vectors USING ivfflat (embedding vector_l2_ops) 
WITH (lists = 1);

-- 8. 인덱스를 사용한 검색 테스트
EXPLAIN (ANALYZE, BUFFERS) 
SELECT name, embedding <-> '[2, 2, 2]' as distance
FROM test_vectors
ORDER BY embedding <-> '[2, 2, 2]'
LIMIT 2;

-- 9. 벡터 차원 확인
SELECT 
    name,
    embedding,
    vector_dims(embedding) as dimensions
FROM test_vectors;

-- 10. 정리 (선택사항)
-- DROP TABLE test_vectors;

-- 결과 메시지
SELECT 'pgvector 확장이 정상적으로 작동하고 있습니다!' as test_result;