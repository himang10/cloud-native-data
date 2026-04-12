#!/bin/bash

# MariaDB 연결 정보
MARIADB_HOST="${MARIADB_HOST:-localhost}"
MARIADB_PORT="${MARIADB_PORT:-3306}"
MARIADB_USER="${MARIADB_USER:-skala}"
MARIADB_PASSWORD="${MARIADB_PASSWORD:-Skala25a!23\$}"
MARIADB_DATABASE="${MARIADB_DATABASE:-cloud}"
RESET_DOMAIN="${RESET_DOMAIN:-false}"  # true로 설정 시 users/orders/order_items/products 초기화

echo "===================================="
echo "Outbox 테이블 초기화"
echo "===================================="
echo "호스트: ${MARIADB_HOST}:${MARIADB_PORT}"
echo "데이터베이스: ${MARIADB_DATABASE}"
echo "도메인 테이블 리셋(RESET_DOMAIN): ${RESET_DOMAIN}"
echo ""

# SQL 파일 생성
SQL_FILE="/tmp/init-outbox-table.sql"

if [ "${RESET_DOMAIN}" = "true" ]; then
  echo "도메인 테이블(users/orders/order_items/products) 및 FK를 초기화하는 SQL을 포함합니다."
  cat > "${SQL_FILE}" << 'EOF'
-- cloud 데이터베이스 사용
USE cloud;

-- FK 무시하고 도메인 테이블 제거(있다면)
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS products;
SET FOREIGN_KEY_CHECKS = 1;

-- outbox_events 재생성
DROP TABLE IF EXISTS outbox_events;

CREATE TABLE outbox_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_id CHAR(36) NOT NULL UNIQUE,
    aggregate_id BIGINT NOT NULL,
    aggregate_type VARCHAR(255) NOT NULL,
    event_type VARCHAR(255) NOT NULL,
    payload JSON NOT NULL,
    occurred_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    processed TINYINT(1) NOT NULL DEFAULT 0,
    INDEX idx_event_id (event_id),
    INDEX idx_aggregate (aggregate_type, aggregate_id),
    INDEX idx_occurred_at (occurred_at),
    INDEX idx_processed (processed)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 샘플 이벤트 데이터 삽입
INSERT INTO outbox_events (event_id, aggregate_id, aggregate_type, event_type, payload, processed) VALUES
    (UUID(), 1, 'user', 'created', JSON_OBJECT(
        'id', 1,
        'name', 'John Doe',
        'email', 'john@example.com'
    ), 0),
    (UUID(), 2, 'user', 'created', JSON_OBJECT(
        'id', 2,
        'name', 'Jane Smith',
        'email', 'jane@example.com'
    ), 0),
    (UUID(), 1001, 'order', 'created', JSON_OBJECT(
        'id', 1001,
        'userId', 1,
        'orderNumber', 'ORD-1001',
        'status', 'COMPLETED',
        'totalAmount', 1200.00
    ), 0),
    (UUID(), 1002, 'order', 'created', JSON_OBJECT(
        'id', 1002,
        'userId', 2,
        'orderNumber', 'ORD-1002',
        'status', 'PENDING',
        'totalAmount', 51.98
    ), 0),
    (UUID(), 101, 'product', 'created', JSON_OBJECT(
        'id', 101,
        'name', 'Laptop',
        'description', 'High-performance laptop',
        'price', 1200.00,
        'stock', 10
    ), 0);

-- 확인
SELECT 'Outbox Events' as info, COUNT(*) as count FROM outbox_events;
SELECT id, event_id, aggregate_type, aggregate_id, event_type, processed, occurred_at 
FROM outbox_events 
ORDER BY occurred_at;
EOF
else
  cat > "${SQL_FILE}" << 'EOF'
-- cloud 데이터베이스 사용
USE cloud;

-- 기존 테이블 삭제 (존재하는 경우)
DROP TABLE IF EXISTS outbox_events;

-- outbox_events 테이블 생성 (Java Entity와 동일한 구조)
CREATE TABLE outbox_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_id CHAR(36) NOT NULL UNIQUE,
    aggregate_id BIGINT NOT NULL,
    aggregate_type VARCHAR(255) NOT NULL,
    event_type VARCHAR(255) NOT NULL,
    payload JSON NOT NULL,
    occurred_at TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    processed TINYINT(1) NOT NULL DEFAULT 0,
    INDEX idx_event_id (event_id),
    INDEX idx_aggregate (aggregate_type, aggregate_id),
    INDEX idx_occurred_at (occurred_at),
    INDEX idx_processed (processed)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 샘플 이벤트 데이터 삽입 (aggregate_id를 BIGINT로 변경)
INSERT INTO outbox_events (event_id, aggregate_id, aggregate_type, event_type, payload, processed) VALUES
    (UUID(), 1, 'user', 'created', JSON_OBJECT(
        'id', 1,
        'name', 'John Doe',
        'email', 'john@example.com'
    ), 0),
    (UUID(), 2, 'user', 'created', JSON_OBJECT(
        'id', 2,
        'name', 'Jane Smith',
        'email', 'jane@example.com'
    ), 0),
    (UUID(), 1001, 'order', 'created', JSON_OBJECT(
        'id', 1001,
        'userId', 1,
        'orderNumber', 'ORD-1001',
        'status', 'COMPLETED',
        'totalAmount', 1200.00
    ), 0),
    (UUID(), 1002, 'order', 'created', JSON_OBJECT(
        'id', 1002,
        'userId', 2,
        'orderNumber', 'ORD-1002',
        'status', 'PENDING',
        'totalAmount', 51.98
    ), 0),
    (UUID(), 101, 'product', 'created', JSON_OBJECT(
        'id', 101,
        'name', 'Laptop',
        'description', 'High-performance laptop',
        'price', 1200.00,
        'stock', 10
    ), 0);

-- 테이블 확인
SELECT 'Outbox Events' as info, COUNT(*) as count FROM outbox_events;
SELECT id, event_id, aggregate_type, aggregate_id, event_type, processed, occurred_at 
FROM outbox_events 
ORDER BY occurred_at;
EOF
fi

echo "SQL 파일 생성 완료: ${SQL_FILE}"
echo ""

# MariaDB에 SQL 실행
echo "MariaDB에 연결하여 테이블 생성 중..."

# docker exec로 SQL 파일 복사 후 실행
docker cp "${SQL_FILE}" mariadb-cdc:/tmp/init-outbox-table.sql

if docker exec mariadb-cdc bash -c "mysql -u${MARIADB_USER} -p${MARIADB_PASSWORD} ${MARIADB_DATABASE} < /tmp/init-outbox-table.sql"; then
    echo ""
    echo "✅ 성공: Outbox 테이블과 샘플 데이터가 생성되었습니다."
    echo ""
    
    # 테이블 구조 확인
    echo "테이블 구조:"
    docker exec mariadb-cdc mysql -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" "${MARIADB_DATABASE}" \
        -e "DESCRIBE outbox_events;"
    
    echo ""
    echo "샘플 데이터:"
    docker exec mariadb-cdc mysql -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" "${MARIADB_DATABASE}" \
        -e "SELECT id, event_id, aggregate_type, aggregate_id, event_type, processed FROM outbox_events;"
else
    echo "❌ 오류: 테이블 생성 실패"
    docker exec mariadb-cdc rm -f /tmp/init-outbox-table.sql
    exit 1
fi

# 임시 파일 삭제
rm -f "${SQL_FILE}"
docker exec mariadb-cdc rm -f /tmp/init-outbox-table.sql

echo ""
echo "===================================="
echo "초기화 완료"
echo "===================================="
echo "다음 단계:"
echo "1. 커넥터 등록: ./register-connector.sh mariadb-outbox-connector.json"
echo "2. 커넥터 확인: ./check-connector.sh mariadb-outbox-connector"
echo "3. Kafka 토픽 확인: docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list | grep outbox"
