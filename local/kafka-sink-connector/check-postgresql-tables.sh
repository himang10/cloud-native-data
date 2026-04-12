#!/bin/bash

# PostgreSQL 연결 정보
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5433}"
PGUSER="${PGUSER:-postgres}"
PGPASSWORD="${PGPASSWORD:-postgres}"
PGDATABASE="${PGDATABASE:-cloud}"

echo "===================================="
echo "PostgreSQL CDC 테이블 확인"
echo "===================================="
echo "호스트: ${PGHOST}:${PGPORT}"
echo "데이터베이스: ${PGDATABASE}"
echo ""

# 테이블 목록 확인
echo "CDC 테이블 목록:"
docker exec pgvector psql -U "${PGUSER}" -d "${PGDATABASE}" -c "
SELECT
    tablename,
    schemaname
FROM pg_tables
WHERE tablename LIKE 'cdc_%'
ORDER BY tablename;
"

echo ""
echo "===================================="
echo "각 테이블의 레코드 수"
echo "===================================="

# cdc_users 테이블
echo ""
echo "1. cdc_users:"
docker exec pgvector psql -U "${PGUSER}" -d "${PGDATABASE}" -c "
SELECT COUNT(*) as total_rows FROM cdc_users;
" 2>/dev/null || echo "테이블이 아직 생성되지 않았습니다."

# cdc_products 테이블
echo ""
echo "2. cdc_products:"
docker exec pgvector psql -U "${PGUSER}" -d "${PGDATABASE}" -c "
SELECT COUNT(*) as total_rows FROM cdc_products;
" 2>/dev/null || echo "테이블이 아직 생성되지 않았습니다."

# cdc_orders 테이블
echo ""
echo "3. cdc_orders:"
docker exec pgvector psql -U "${PGUSER}" -d "${PGDATABASE}" -c "
SELECT COUNT(*) as total_rows FROM cdc_orders;
" 2>/dev/null || echo "테이블이 아직 생성되지 않았습니다."

echo ""
echo "===================================="
echo "샘플 데이터 확인 (최근 5건)"
echo "===================================="

echo ""
echo "cdc_users:"
docker exec pgvector psql -U "${PGUSER}" -d "${PGDATABASE}" -c "
SELECT * FROM cdc_users ORDER BY id LIMIT 5;
" 2>/dev/null || echo "테이블이 아직 생성되지 않았습니다."

echo ""
echo "cdc_products:"
docker exec pgvector psql -U "${PGUSER}" -d "${PGDATABASE}" -c "
SELECT * FROM cdc_products ORDER BY id LIMIT 5;
" 2>/dev/null || echo "테이블이 아직 생성되지 않았습니다."

echo ""
echo "cdc_orders:"
docker exec pgvector psql -U "${PGUSER}" -d "${PGDATABASE}" -c "
SELECT * FROM cdc_orders ORDER BY id LIMIT 5;
" 2>/dev/null || echo "테이블이 아직 생성되지 않았습니다."
