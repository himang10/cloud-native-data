-- Debezium CDC 전용 사용자 권한 설정
-- (MARIADB_USER=skala 로 이미 생성된 경우 권한만 부여)

-- Debezium 필수 권한 부여
GRANT SELECT, RELOAD, SHOW DATABASES, REPLICATION SLAVE, REPLICATION CLIENT
  ON *.* TO 'skala'@'%';

-- cloud 데이터베이스 전체 권한
GRANT ALL PRIVILEGES ON cloud.* TO 'skala'@'%';

FLUSH PRIVILEGES;

-- CDC 테스트용 테이블
USE cloud;

CREATE TABLE IF NOT EXISTS users (
    id            BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id       VARCHAR(100) NOT NULL UNIQUE,
    user_email    VARCHAR(200) NOT NULL,
    user_name     VARCHAR(100),
    user_password VARCHAR(255),
    user_role     VARCHAR(50) DEFAULT 'USER',
    created_at    DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
