-- ==========================================
-- 샘플 데이터 삽입 (테스트용)
-- ==========================================
USE cloud;

-- 샘플 사용자 데이터
INSERT INTO users (name, email) VALUES
('홍길동', 'hong@example.com'),
('김철수', 'kim@example.com'),
('이영희', 'lee@example.com')
ON DUPLICATE KEY UPDATE name=VALUES(name);

-- 샘플 상품 데이터
INSERT INTO products (name, description, price, stock) VALUES
('MacBook Pro', '16-inch, M3 Pro', 2990000.00, 10),
('iPhone 15 Pro', '256GB, Titanium', 1550000.00, 25),
('AirPods Pro', '2nd Generation', 359000.00, 50)
ON DUPLICATE KEY UPDATE name=VALUES(name);

-- 데이터 확인
SELECT * FROM users;
SELECT * FROM products;

