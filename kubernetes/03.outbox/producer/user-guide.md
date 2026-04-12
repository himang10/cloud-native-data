# Outbox Pattern Producer 실습 가이드

## 1. 전체 개념

### Outbox Pattern이란?

Outbox Pattern은 마이크로서비스 아키텍처에서 이벤트 기반 통신을 구현하는 패턴입니다. 이 패턴은 다음과 같은 문제를 해결합니다:

- **트랜잭션 일관성**: 도메인 데이터와 이벤트를 하나의 트랜잭션에 묶어 원자성을 보장
- **신뢰성**: 애플리케이션 중단 시에도 이벤트 손실 방지
- **멱등성**: 동일한 이벤트가 여러 번 전송되어도 안전하게 처리

### 동작 원리

1. **애플리케이션**: 도메인 데이터 변경 시 `outbox_events` 테이블에 이벤트를 함께 저장
2. **CDC (Change Data Capture)**: Debezium 같은 도구가 데이터베이스 변경 로그를 모니터링
3. **이벤트 발행**: CDC가 이벤트를 감지하여 Kafka 토픽으로 자동 발행
4. **소비자**: 다른 서비스가 Kafka에서 이벤트를 구독하여 처리

### 프로젝트 구성

이 프로젝트는 온라인 쇼핑몰의 간소화된 버전으로, 다음 도메인을 다룹니다:

- **User**: 고객 정보 관리
- **Product**: 상품 정보 관리
- **Order**: 주문 정보 관리
- **OrderItem**: 주문 상세 내역 (특정 제품, 수량, 가격)
- **OutboxEvent**: 도메인 이벤트 저장소

---

## 2. 목적 및 용도

### 주요 목적

이 실습 프로젝트는 다음을 학습하기 위한 것입니다:

1. **Outbox Pattern 구현 방법**: 트랜잭션 내에서 도메인 데이터와 이벤트를 함께 저장하는 방법
2. **Spring Boot와 JPA 활용**: 엔티티 설계, 트랜잭션 관리, JPA 어노테이션 사용
3. **REST API 설계**: RESTful 원칙에 따른 API 엔드포인트 설계
4. **이벤트 기반 아키텍처**: 이벤트 소싱 패턴의 기본 개념 이해
5. **CDC 연동 준비**: Debezium 등 CDC 도구와 연동할 수 있는 데이터 구조 이해

### 실무 적용 사례

- 전자상거래 주문 처리 시스템
- 사용자 프로필 변경 알림 시스템
- 재고 관리 및 동기화 시스템
- 마이크로서비스 간 데이터 일관성 유지

---

## 3. 파일별 설명

### 3.1 프로젝트 설정 파일

#### pom.xml

Maven 프로젝트 설정 파일로, 프로젝트 메타데이터와 의존성을 정의합니다.

**주요 설정:**

```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.5</version>
</parent>
```

- Spring Boot 3.3.5 버전 사용
- Java 21을 타겟으로 설정

**주요 의존성:**

- `spring-boot-starter-web`: REST API 구현을 위한 웹 프레임워크
- `spring-boot-starter-data-jpa`: JPA를 사용한 데이터베이스 접근
- `mariadb-java-client`: MariaDB 데이터베이스 드라이버
- `lombok`: 보일러플레이트 코드 감소 (getter, setter, builder 등)
- `spring-boot-starter-actuator`: 애플리케이션 모니터링 및 헬스체크
- `jackson-databind`: JSON 직렬화/역직렬화

#### application.yml

모든 환경에서 공통으로 사용되는 설정입니다.

**데이터베이스 설정:**
```yaml
spring:
  datasource:
    url: jdbc:mariadb://호스트:포트/데이터베이스
    username: 데이터베이스_사용자
    password: 비밀번호
    hikari:
      maximum-pool-size: 10  # 최대 커넥션 풀 크기
```

**JPA 설정:**
```yaml
spring:
  jpa:
    hibernate:
      ddl-auto: update  # 자동으로 스키마 생성/업데이트
    show-sql: true      # SQL 쿼리 로그 출력
```

**서버 설정:**
```yaml
server:
  port: 8080            # 웹 서버 포트
  shutdown: graceful    # 종료 시 진행 중인 요청 완료 대기
```

#### application-local.yml

로컬 개발 환경 전용 설정입니다.

**특징:**
- SQL 쿼리 로그 출력 활성화
- 상세한 로그 레벨 설정
- 헬스체크 상세 정보 표시

#### env.example

환경 변수 설정 예제 파일입니다. 로컬 실행 시 `.env` 파일로 복사하여 사용합니다.

**주요 환경 변수:**
- `SPRING_PROFILES_ACTIVE`: 활성화할 프로파일 (local/prod)
- `DB_URL`: 데이터베이스 연결 URL
- `DB_USERNAME`: 데이터베이스 사용자명
- `DB_PASSWORD`: 데이터베이스 비밀번호
- `SERVER_PORT`: 서버 포트 번호

### 3.2 SQL 스크립트

#### cleanup_tables.sql

데이터베이스 초기화용 스크립트입니다.

**용도:**
- 실습 전 데이터 정리
- outbox_events를 제외한 모든 테이블 삭제
- 테스트 시작 시 깨끗한 상태로 초기화

**사용 예시:**
```sql
-- 모든 테이블 목록 확인
SHOW TABLES;

-- 불필요한 테이블 삭제
DROP TABLE IF EXISTS users;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS products;
```

### 3.3 Shell 스크립트 (사용 방법)

#### script/create-users.sh

여러 사용자를 일괄 생성하는 스크립트입니다.

**사용법:**
```bash
# 기본 사용자 전체 생성 (10명)
./script/create-users.sh

# 지정된 수만큼 생성
./script/create-users.sh 5

# 랜덤 사용자 생성
./script/create-users.sh random 10

# 대화형 모드로 생성
./script/create-users.sh custom
```

**주요 기능:**
- 서버 연결 상태 자동 확인
- 생성 성공/실패 개수 표시
- 색상으로 구분된 출력
- 각 API 호출 간 딜레이 적용

#### script/call-user.sh

단일 사용자를 생성하는 기본 스크립트입니다.

**사용법:**
```bash
./script/call-user.sh "홍길동" "hong@example.com"
```

#### script/update-user.sh

사용자 정보를 수정하는 스크립트입니다.

**사용법:**
```bash
./script/update-user.sh 1 "홍길동" "hong_new@example.com"
```

### 3.4 Docker 설정

#### Dockerfile

애플리케이션을 컨테이너 이미지로 빌드하기 위한 설정입니다.

**Multi-stage Build:**
1. **Builder Stage**: Maven을 사용하여 애플리케이션 빌드
2. **Runtime Stage**: JRE만 포함된 경량 이미지로 실행

**빌드 및 실행:**
```bash
# 이미지 빌드
docker build -t outbox-producer:latest .

# 컨테이너 실행
docker run -p 8080:8080 \
  -e DB_URL=jdbc:mariadb://호스트:3306/cloud \
  -e DB_USERNAME=사용자명 \
  -e DB_PASSWORD=비밀번호 \
  outbox-producer:latest
```

---

## 4. 실습 절차

### 4.1 사전 준비

#### 1) 환경 요구사항 확인

```bash
# Java 버전 확인 (21 이상)
java -version

# Maven 설치 확인
mvn -v

# MariaDB 접속 가능 여부 확인
mysql -h 호스트 -u 사용자명 -p 데이터베이스명
```

#### 2) 데이터베이스 테이블 확인

```sql
USE cloud;

-- 기존 테이블 확인
SHOW TABLES;

-- outbox_events 테이블이 없으면 생성
CREATE TABLE IF NOT EXISTS outbox_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_id CHAR(36) NOT NULL UNIQUE,
    aggregate_id BIGINT NOT NULL,
    aggregate_type VARCHAR(255) NOT NULL,
    event_type VARCHAR(255) NOT NULL,
    payload JSON NOT NULL,
    occurred_at TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    processed TINYINT(1) DEFAULT 0,
    INDEX idx_processed (processed),
    INDEX idx_aggregate (aggregate_type, aggregate_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
```

### 4.2 애플리케이션 실행

#### 방법 1: Maven을 통한 실행

```bash
# 프로젝트 루트 디렉토리에서 실행
mvn spring-boot:run

# 특정 프로파일 지정
mvn spring-boot:run -Dspring-boot.run.profiles=local
```

#### 방법 2: JAR 파일 실행

```bash
# 빌드
mvn clean package -DskipTests

# 실행
java -jar target/outbox-producer-1.0.0.jar

# 환경 변수 지정
java -jar target/outbox-producer-1.0.0.jar \
  --spring.profiles.active=local
```

#### 방법 3: Docker로 실행

```bash
# 이미지 빌드
docker build -t outbox-producer:latest .

# 컨테이너 실행 (환경 변수는 .env 파일 사용)
docker run -p 8080:8080 --env-file .env outbox-producer:latest
```

### 4.3 서버 상태 확인

```bash
# 헬스체크 확인
curl http://localhost:8080/actuator/health

# 예상 응답:
# {"status":"UP"}

# 상세 정보 확인 (로컬 프로파일)
curl http://localhost:8080/actuator/health | jq .
```

### 4.4 실습 시나리오

#### 시나리오 1: 사용자 생성 및 이벤트 확인

**1단계: 사용자 생성**

```bash
curl -X POST http://localhost:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "홍길동",
    "email": "hong@example.com"
  }' | jq .
```

**2단계: 생성된 사용자 확인**

```bash
# 모든 사용자 조회
curl http://localhost:8080/api/users | jq .
```

**3단계: Outbox 이벤트 확인**

```sql
-- MariaDB에 접속하여 확인
SELECT * FROM outbox_events ORDER BY id DESC LIMIT 10;
```

**확인 포인트:**
- `aggregate_type`이 "user"인지 확인
- `event_type`이 "created"인지 확인
- `payload`에 사용자 정보가 JSON 형식으로 저장되어 있는지 확인

#### 시나리오 2: 상품 생성

```bash
# 상품 생성
curl -X POST http://localhost:8080/api/products \
  -H "Content-Type: application/json" \
  -d '{
    "name": "노트북",
    "description": "고성능 노트북",
    "price": 1500000,
    "stock": 10
  }' | jq .
```

#### 시나리오 3: 주문 생성

```bash
# 주문 생성
curl -X POST http://localhost:8080/api/orders \
  -H "Content-Type: application/json" \
  -d '{
    "userId": 1,
    "orderNumber": "ORD-2024-001",
    "status": "PENDING",
    "totalAmount": 1500000
  }' | jq .
```

#### 시나리오 4: 사용자 정보 수정 및 이벤트 확인

```bash
# 사용자 정보 수정
curl -X PUT http://localhost:8080/api/users/1 \
  -H "Content-Type: application/json" \
  -d '{
    "name": "홍길동",
    "email": "hong_updated@example.com"
  }' | jq .
```

**Outbox 이벤트 확인:**
```sql
SELECT * FROM outbox_events 
WHERE aggregate_type = 'user' 
ORDER BY id DESC LIMIT 5;
```

**예상 결과:**
- 이전 "created" 이벤트가 남아있고
- 새로운 "updated" 이벤트가 추가됨

#### 시나리오 5: 일괄 사용자 생성

```bash
# script 디렉토리로 이동
cd script

# 실행 권한 부여
chmod +x create-users.sh call-user.sh

# 기본 사용자 5명 생성
./create-users.sh 5
```

### 4.5 트랜잭션 확인

**목적:** Outbox Pattern의 핵심인 트랜잭션 원자성을 확인합니다.

**테스트 1: 정상 케이스**

1. 사용자 생성 API 호출
2. 데이터베이스에서 확인:
   - `users` 테이블에 레코드 생성
   - `outbox_events` 테이블에 이벤트 생성
3. 두 개가 모두 존재하는지 확인

**테스트 2: 롤백 시나리오**

```sql
-- 트랜잭션 시작
START TRANSACTION;

-- 사용자 삭제 시도 (외래키 제약으로 실패하면)
DELETE FROM users WHERE id = 1;

-- Outbox 이벤트는 삭제되지 않아야 함
SELECT COUNT(*) FROM outbox_events WHERE aggregate_id = 1;

-- 롤백
ROLLBACK;
```

---

## 5. 실행 결과 확인 방법

### 5.1 애플리케이션 로그 확인

**실행 중 로그에서 확인할 내용:**

```
2024-01-01 10:00:00 - Creating user: email=hong@example.com
2024-01-01 10:00:00 - User created successfully: id=1, email=hong@example.com
2024-01-01 10:00:00 - Outbox event published: eventId=uuid, aggregateType=user, eventType=created, aggregateId=1
```

**로그 레벨 조정:**
```yaml
logging:
  level:
    com.example.producer: DEBUG  # 상세 로그 출력
```

### 5.2 데이터베이스 확인

#### 사용자 데이터 확인

```sql
SELECT * FROM users;
```

#### Outbox 이벤트 확인

```sql
-- 전체 이벤트 조회
SELECT * FROM outbox_events ORDER BY id DESC;

-- 특정 타입의 이벤트만 조회
SELECT * FROM outbox_events 
WHERE aggregate_type = 'user' 
ORDER BY occurred_at DESC;

-- 이벤트 내용 상세 확인 (MariaDB JSON 함수 사용)
SELECT 
    id,
    event_id,
    aggregate_type,
    event_type,
    JSON_PRETTY(payload) as payload,
    occurred_at,
    processed
FROM outbox_events
WHERE id = 1;
```

#### 통계 확인

```sql
-- 도메인별 이벤트 개수
SELECT aggregate_type, COUNT(*) as count
FROM outbox_events
GROUP BY aggregate_type;

-- 이벤트 타입별 개수
SELECT event_type, COUNT(*) as count
FROM outbox_events
GROUP BY event_type;

-- 처리되지 않은 이벤트 개수
SELECT COUNT(*) FROM outbox_events WHERE processed = 0;
```

### 5.3 REST API 응답 확인

#### 성공 응답 예시

```json
{
  "id": 1,
  "name": "홍길동",
  "email": "hong@example.com",
  "createdAt": "2024-01-01T10:00:00",
  "updatedAt": "2024-01-01T10:00:00"
}
```

#### 에러 응답 예시

```json
{
  "timestamp": "2024-01-01T10:00:00.000+00:00",
  "status": 404,
  "error": "Not Found",
  "message": "User not found: id=999",
  "path": "/api/users/999"
}
```

### 5.4 헬스체크 확인

```bash
# 기본 헬스체크
curl http://localhost:8080/actuator/health

# 상세 정보 (로컬 프로파일)
curl http://localhost:8080/actuator/health | jq .

# 데이터베이스 연결 확인
curl http://localhost:8080/actuator/health/db | jq .
```

### 5.5 테이블 스키마 확인

```sql
-- users 테이블 구조
DESCRIBE users;

-- outbox_events 테이블 구조
DESCRIBE outbox_events;

-- 인덱스 확인
SHOW INDEX FROM outbox_events;
```

---

## 6. 실습 체크리스트

### 기본 기능
- [ ] 애플리케이션 정상 실행
- [ ] 헬스체크 응답 확인
- [ ] 사용자 생성 성공
- [ ] 사용자 수정 성공
- [ ] 사용자 삭제 성공
- [ ] 사용자 조회 성공

### Outbox Pattern 검증
- [ ] 사용자 생성 시 outbox_events에 레코드 생성
- [ ] 사용자 수정 시 outbox_events에 레코드 생성
- [ ] 사용자 삭제 시 outbox_events에 레코드 생성
- [ ] 이벤트 payload에 정확한 데이터 포함
- [ ] aggregate_type, event_type 값이 올바름

### 상품 관리
- [ ] 상품 생성 성공
- [ ] 상품 수정 성공
- [ ] 상품 삭제 성공
- [ ] 상품 조회 성공

### 주문 관리
- [ ] 주문 생성 성공
- [ ] 주문 상태 변경 성공
- [ ] 주문 조회 성공
- [ ] 사용자별 주문 조회 성공

### 데이터베이스 검증
- [ ] 모든 테이블 정상 생성
- [ ] outbox_events 테이블에 인덱스 존재
- [ ] 트랜잭션 원자성 보장 확인

---

## 7. 트러블슈팅

### 서버가 시작되지 않음

**원인:**
- 데이터베이스 연결 실패
- 포트 충돌
- 필수 환경 변수 미설정

**해결 방법:**
```bash
# 로그 확인
tail -f logs/application.log

# 포트 사용 확인
lsof -i :8080

# 데이터베이스 연결 테스트
mysql -h 호스트 -u 사용자명 -p 데이터베이스명
```

### 데이터베이스 연결 실패

**확인 사항:**
- DB_URL, DB_USERNAME, DB_PASSWORD 환경 변수 확인
- 방화벽 설정 확인
- 데이터베이스 서버 실행 상태 확인

**해결 방법:**
```bash
# 환경 변수 확인
env | grep DB_

# application.yml 확인
cat src/main/resources/application.yml
```

### Outbox 이벤트가 생성되지 않음

**확인 사항:**
- 서비스 코드에서 `outboxService.publishEvent()` 호출 여부
- 트랜잭션이 정상 커밋되었는지
- 로그에 에러 메시지 확인

**해결 방법:**
```bash
# 로그 확인
grep -i "outbox" logs/application.log

# 데이터베이스 직접 확인
SELECT * FROM outbox_events ORDER BY id DESC LIMIT 10;
```

### 외래키 제약 오류

**원인:**
- 존재하지 않는 userId로 주문 생성
- 존재하지 않는 productId로 OrderItem 생성

**해결 방법:**
- 먼저 참조하는 엔티티가 존재하는지 확인
- API 호출 순서 확인 (User → Order → OrderItem)

---

## 8. 다음 단계

### 고급 실습

1. **CDC 연동**: Debezium Connector 설정 및 Kafka 연결
2. **이벤트 처리**: Outbox 이벤트의 processed 플래그 관리
3. **멱등성 구현**: event_id 기반 중복 처리 방지
4. **테스트 코드 작성**: JUnit 기반 통합 테스트

### 참고 문서

- [source-code-guide.md](./source-code-guide.md): 소스 코드 상세 설명
- [README-CONFIG.md](./README-CONFIG.md): 설정 파일 상세 설명
- Spring Boot 공식 문서: https://spring.io/projects/spring-boot
- Outbox Pattern: https://microservices.io/patterns/data/transactional-outbox.html

---

## 9. 결론

이 실습을 통해 다음을 학습했습니다:

1. **Outbox Pattern의 기본 개념**과 구현 방법
2. **Spring Boot와 JPA**를 활용한 엔티티 설계 및 트랜잭션 관리
3. **REST API 설계 및 테스트** 방법
4. **이벤트 기반 아키텍처**의 기초

다음 단계로 CDC (Change Data Capture) 도구인 Debezium을 연동하여 실제로 Kafka로 이벤트를 발행하는 실습을 진행할 수 있습니다.

