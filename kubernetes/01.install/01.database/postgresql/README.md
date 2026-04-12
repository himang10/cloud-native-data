# PostgreSQL with pgvector Extension

## pgvector 확장 기능

이 PostgreSQL 인스턴스는 pgvector 확장이 활성화되어 있어 벡터 데이터 타입과 유사도 검색을 지원합니다.

### 빠른 시작

```bash
# pgvector 확장 활성화 (필요시)
./enable-pgvector.sh

# pgvector 기능 테스트
./test-pgvector-simple.sh
```

### 사용 예제

```sql
-- 확장 확인
SELECT * FROM pg_extension WHERE extname = 'vector';

-- 벡터 테이블 생성 예제
CREATE TABLE documents (
    id SERIAL PRIMARY KEY,
    title TEXT,
    content TEXT,
    embedding VECTOR(1536)  -- OpenAI 임베딩 차원
);

-- 벡터 인덱스 생성 (성능 향상)
CREATE INDEX ON documents USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- 벡터 삽입 예제
INSERT INTO documents (title, content, embedding) 
VALUES ('Sample', 'This is a sample document', '[0.1, 0.2, 0.3, ...]');

-- 코사인 유사도 검색
SELECT title, content, 1 - (embedding <=> '[query_vector]') AS similarity
FROM documents
ORDER BY embedding <=> '[query_vector]'
LIMIT 5;
```

### 지원하는 거리 함수
- `<->` : L2 거리 (유클리디안)
- `<#>` : 내적 거리 (음수)
- `<=>` : 코사인 거리

### 인덱스 타입
- IVFFlat: 근사 최근접 이웃 검색
- HNSW: 계층적 탐색 가능한 소세계 그래프 (향후 지원 예정)

## kubernetes 배포 현황
- **namespace**: kafka
- **이미지**: `docker.io/bitnamilegacy/postgresql` (bitnami/postgresql 차트)
- **Helm 차트**: `bitnami/postgresql 16.7.4` (App: PostgreSQL 17.5.0)
- **Pod**: `postgres-1-postgresql-0`
- **서비스**: `postgres-1-postgresql:5432`

## 내부 접속 (클러스터 내 Pod 간)
```
postgres-1-postgresql.kafka.svc.cluster.local:5432
postgres-1-postgresql.kafka:5432
```

## 계정 정보

### admin
- UserName: `postgres`
- Password: `Skala25a!23$`

### 일반 사용자
- Database: `cloud`
- UserName: `skala`
- Password: `Skala25a!23$`

## 설치 / 삭제
```bash
# 설치
bash install.sh

# 삭제
bash uninstall.sh
```
