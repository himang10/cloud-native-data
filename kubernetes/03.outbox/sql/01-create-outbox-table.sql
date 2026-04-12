-- ==========================================
-- Outbox Pattern용 테이블 생성
-- ==========================================
-- 데이터베이스: cloud (기존 CDC와 동일)
-- 용도: Debezium Outbox Event Router와 함께 사용

USE cloud;

-- outbox_events 테이블 생성
CREATE TABLE IF NOT EXISTS outbox_events (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  
  -- 이벤트 고유 ID (멱등성 보장)
  event_id CHAR(36) UNIQUE NOT NULL COMMENT 'UUID 이벤트 ID',
  
  -- 집합 루트 정보
  aggregate_id BIGINT NOT NULL COMMENT '집합 루트 ID (예: user_id, order_id, product_id)',
  aggregate_type VARCHAR(100) NOT NULL COMMENT '집합 타입 (예: USER, ORDER, PRODUCT)',
  
  -- 이벤트 정보
  event_type VARCHAR(100) NOT NULL COMMENT '이벤트 타입 (예: CREATED, UPDATED, DELETED)',
  payload JSON NOT NULL COMMENT '이벤트 페이로드 (JSON 형식)',
  
  -- 타임스탬프
  occurred_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3) COMMENT '이벤트 발생 시간',
  
  -- 처리 상태 (선택사항)
  processed TINYINT(1) DEFAULT 0 COMMENT '처리 여부 (0: 미처리, 1: 처리 완료)',
  
  -- 인덱스
  INDEX idx_aggregate_type (aggregate_type),
  INDEX idx_aggregate_id (aggregate_id),
  INDEX idx_occurred_at (occurred_at),
  INDEX idx_processed (processed)
  
) ENGINE=InnoDB 
  DEFAULT CHARSET=utf8mb4 
  COLLATE=utf8mb4_unicode_ci 
  COMMENT='Outbox Pattern 이벤트 저장소';

-- 테이블 생성 확인
SELECT 
    TABLE_NAME,
    TABLE_ROWS,
    CREATE_TIME,
    TABLE_COMMENT
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'cloud' 
  AND TABLE_NAME = 'outbox_events';

-- 테이블 구조 확인
DESCRIBE outbox_events;

-- ==========================================
-- 기존 도메인 테이블 확인 (이미 존재하는 경우 스킵)
-- ==========================================

-- users 테이블 (이미 존재하는 경우 생략)
CREATE TABLE IF NOT EXISTS users (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(100) UNIQUE NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- products 테이블
CREATE TABLE IF NOT EXISTS products (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(200) NOT NULL,
  description TEXT,
  price DECIMAL(10,2) NOT NULL,
  stock INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- orders 테이블
CREATE TABLE IF NOT EXISTS orders (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  user_id BIGINT NOT NULL,
  order_number VARCHAR(50) UNIQUE NOT NULL,
  status VARCHAR(50) DEFAULT 'PENDING',
  total_amount DECIMAL(10,2) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (user_id) REFERENCES users(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- order_items 테이블
CREATE TABLE IF NOT EXISTS order_items (
  id BIGINT AUTO_INCREMENT PRIMARY KEY,
  order_id BIGINT NOT NULL,
  product_id BIGINT NOT NULL,
  quantity INT NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (order_id) REFERENCES orders(id),
  FOREIGN KEY (product_id) REFERENCES products(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ==========================================
-- 생성된 테이블 목록 확인
-- ==========================================
SHOW TABLES FROM cloud;

-- ==========================================
-- 완료 메시지
-- ==========================================
SELECT 'Outbox 테이블이 cloud 데이터베이스에 성공적으로 생성되었습니다!' AS message;

