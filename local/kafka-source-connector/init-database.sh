#!/bin/bash

# MariaDB 연결 정보
MARIADB_HOST="${MARIADB_HOST:-localhost}"
MARIADB_PORT="${MARIADB_PORT:-3306}"
MARIADB_USER="${MARIADB_USER:-skala}"
MARIADB_PASSWORD="${MARIADB_PASSWORD:-Skala25a!23\$}"
MARIADB_DATABASE="${MARIADB_DATABASE:-cloud}"

echo "===================================="
echo "MariaDB 샘플 데이터베이스 초기화"
echo "===================================="
echo "호스트: ${MARIADB_HOST}:${MARIADB_PORT}"
echo "데이터베이스: ${MARIADB_DATABASE}"
echo ""

# SQL 파일 생성
SQL_FILE="/tmp/init-cdc-tables.sql"

cat > "${SQL_FILE}" << 'EOF'
-- cloud 데이터베이스 사용
USE cloud;

-- 기존 테이블 삭제 (존재하는 경우, FK 안전)
SET FOREIGN_KEY_CHECKS = 0;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS users;
SET FOREIGN_KEY_CHECKS = 1;

-- users 테이블 생성
CREATE TABLE users (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL UNIQUE,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- products 테이블 생성
CREATE TABLE products (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    price DECIMAL(10, 2) NOT NULL,
    stock INT NOT NULL DEFAULT 0,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- orders 테이블 생성
CREATE TABLE orders (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    order_number VARCHAR(50) NOT NULL UNIQUE,
    status VARCHAR(50) DEFAULT 'PENDING',
    total_amount DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- order_items 테이블 생성
CREATE TABLE order_items (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    order_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    quantity INT NOT NULL,
    price DECIMAL(10, 2) NOT NULL,
    created_at TIMESTAMP NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (order_id) REFERENCES orders(id),
    FOREIGN KEY (product_id) REFERENCES products(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 샘플 데이터 삽입
INSERT INTO users (name, email) VALUES
    ('John Doe', 'john@example.com'),
    ('Jane Smith', 'jane@example.com'),
    ('Bob Wilson', 'bob@example.com');

INSERT INTO products (name, description, price, stock) VALUES
    ('Laptop', 'High-performance laptop', 1200.00, 10),
    ('Mouse', 'Wireless mouse', 25.99, 50),
    ('Keyboard', 'Mechanical keyboard', 89.99, 30),
    ('Monitor', '27-inch 4K monitor', 399.99, 15);

INSERT INTO orders (user_id, order_number, status, total_amount) VALUES
    (1, 'ORD-1001', 'COMPLETED', 1200.00),
    (2, 'ORD-1002', 'PENDING', 51.98),
    (3, 'ORD-1003', 'SHIPPED', 89.99);

INSERT INTO order_items (order_id, product_id, quantity, price) VALUES
    (1, 1, 1, 1200.00),
    (2, 2, 2, 25.99),
    (3, 3, 1, 89.99);

-- 테이블 확인
SELECT 'Users:' as table_name, COUNT(*) as row_count FROM users
UNION ALL
SELECT 'Products:', COUNT(*) FROM products
UNION ALL
SELECT 'Orders:', COUNT(*) FROM orders
UNION ALL
SELECT 'OrderItems:', COUNT(*) FROM order_items;
EOF

echo "SQL 파일 생성 완료: ${SQL_FILE}"
echo ""

# MariaDB에 SQL 실행
echo "MariaDB에 연결하여 테이블 생성 중..."

# docker exec로 SQL 파일 복사 후 실행
docker cp "${SQL_FILE}" mariadb-cdc:/tmp/init-cdc-tables.sql

if docker exec mariadb-cdc bash -c "mysql -u${MARIADB_USER} -p${MARIADB_PASSWORD} ${MARIADB_DATABASE} < /tmp/init-cdc-tables.sql"; then
    echo ""
    echo "✅ 성공: 샘플 테이블과 데이터가 생성되었습니다."
    echo ""
    
    # 테이블 확인
    echo "생성된 테이블:"
    docker exec mariadb-cdc mysql -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" "${MARIADB_DATABASE}" \
        -e "SHOW TABLES;"
    
    echo ""
    echo "데이터 확인:"
    docker exec mariadb-cdc mysql -u"${MARIADB_USER}" -p"${MARIADB_PASSWORD}" "${MARIADB_DATABASE}" \
        -e "SELECT 'Users' as table_name, COUNT(*) as row_count FROM users
            UNION ALL SELECT 'Products', COUNT(*) FROM products
            UNION ALL SELECT 'Orders', COUNT(*) FROM orders;"
else
    echo "❌ 오류: 테이블 생성 실패"
    docker exec mariadb-cdc rm -f /tmp/init-cdc-tables.sql
    exit 1
fi

# 임시 파일 삭제
rm -f "${SQL_FILE}"
docker exec mariadb-cdc rm -f /tmp/init-cdc-tables.sql

echo ""
echo "===================================="
echo "초기화 완료"
echo "===================================="
echo "다음 단계:"
echo "1. 커넥터 등록: ./register-connector.sh mariadb-source-connector.json"
echo "2. 커넥터 확인: ./check-connector.sh mariadb-source-connector"
echo "3. Kafka 토픽 확인: docker exec kafka kafka-topics.sh --bootstrap-server localhost:9092 --list | grep mariadb-cdc"
