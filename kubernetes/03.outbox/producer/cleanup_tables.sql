-- cloud 데이터베이스의 테이블 목록 확인
USE cloud;

-- 모든 테이블 목록 확인
SHOW TABLES;

-- outbox_events를 제외한 모든 테이블 삭제
-- 주의: 이 스크립트는 테이블이 여러 개 있는 경우를 가정합니다

-- users 테이블 삭제 (있다면)
DROP TABLE IF EXISTS users;

-- orders 테이블 삭제 (있다면)
DROP TABLE IF EXISTS orders;

-- order_items 테이블 삭제 (있다면)
DROP TABLE IF EXISTS order_items;

-- products 테이블 삭제 (있다면)
DROP TABLE IF EXISTS products;

-- 기타 JPA가 생성한 테이블들 삭제
SET FOREIGN_KEY_CHECKS = 0;

DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS order_items;
DROP TABLE IF EXISTS products;
DROP TABLE IF EXISTS user;
DROP TABLE IF EXISTS order;
DROP TABLE IF EXISTS order_item;
DROP TABLE IF EXISTS product;

-- FK 체크 재활성화
SET FOREIGN_KEY_CHECKS = 1;

-- 최종 테이블 목록 확인
SHOW TABLES;
