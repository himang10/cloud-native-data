# Outbox Pattern Producer 소스 코드 가이드

## 목차

1. [프로젝트 구조](#1-프로젝트-구조)
2. [의존성 (pom.xml)](#2-의존성-pomxml)
3. [Domain 엔티티](#3-domain-엔티티)
4. [Repository 레이어](#4-repository-레이어)
5. [Service 레이어](#5-service-레이어)
6. [Controller 레이어](#6-controller-레이어)
7. [Configuration](#7-configuration)
8. [주요 의존 관계](#8-주요-의존-관계)
9. [REST API 사용법](#9-rest-api-사용법)

---

## 1. 프로젝트 구조

```
src/main/java/com/example/producer/
├── ProducerApplication.java       # 메인 애플리케이션 진입점
├── config/
│   └── JacksonConfig.java        # Jackson 설정
├── controller/
│   ├── UserController.java       # User REST API
│   ├── OrderController.java      # Order REST API
│   └── ProductController.java    # Product REST API
├── domain/
│   ├── User.java                 # 사용자 엔티티
│   ├── Order.java                # 주문 엔티티
│   ├── OrderItem.java            # 주문 아이템 엔티티
│   ├── Product.java              # 상품 엔티티
│   └── OutboxEvent.java          # Outbox 이벤트 엔티티
├── repository/
│   ├── UserRepository.java       # User 데이터 접근
│   ├── OrderRepository.java      # Order 데이터 접근
│   ├── OrderItemRepository.java  # OrderItem 데이터 접근
│   ├── ProductRepository.java    # Product 데이터 접근
│   └── OutboxEventRepository.java # OutboxEvent 데이터 접근
└── service/
    ├── UserService.java          # User 비즈니스 로직
    ├── OrderService.java         # Order 비즈니스 로직
    ├── OrderItemService.java     # OrderItem 비즈니스 로직
    ├── ProductService.java       # Product 비즈니스 로직
    └── OutboxService.java        # Outbox 이벤트 발행
```

**레이어 아키텍처:**

```
┌─────────────────┐
│   Controller    │  ← REST API 엔드포인트
└────────┬────────┘
         │
┌────────▼────────┐
│    Service      │  ← 비즈니스 로직
└────────┬────────┘
         │
┌────────▼────────┐
│   Repository    │  ← 데이터 접근
└────────┬────────┘
         │
┌────────▼────────┐
│     Domain      │  ← 엔티티
└─────────────────┘
```

---

## 2. 의존성 (pom.xml)

### 2.1 프로젝트 메타데이터

```xml
<groupId>com.example</groupId>
<artifactId>outbox-producer</artifactId>
<version>1.0.0</version>
<name>Outbox Pattern Producer</name>
```

- **GroupId**: 프로젝트 조직 식별자
- **ArtifactId**: JAR 파일명
- **Version**: 릴리스 버전
- **Name**: 프로젝트 이름

### 2.2 Spring Boot 버전

```xml
<parent>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-parent</artifactId>
    <version>3.3.5</version>
</parent>
```

- Spring Boot 3.3.5 버전 사용
- Java 21 호환

### 2.3 주요 의존성

#### spring-boot-starter-web
- **용도**: REST API 구현
- **포함**: Spring MVC, Tomcat, Jackson
- **사용처**: Controller 레이어

#### spring-boot-starter-data-jpa
- **용도**: 데이터베이스 접근
- **포함**: Hibernate ORM, JPA API
- **사용처**: Repository 레이어

#### mariadb-java-client
- **용도**: MariaDB 드라이버
- **버전**: 3.3.3
- **사용처**: 데이터베이스 연결

#### lombok
- **용도**: 보일러플레이트 코드 생성
- **어노테이션**: @Getter, @Setter, @Builder, @NoArgsConstructor 등
- **사용처**: 모든 엔티티 클래스

#### spring-boot-starter-validation
- **용도**: 입력 데이터 검증
- **포함**: Bean Validation API
- **사용처**: Controller 파라미터 검증

#### jackson-databind
- **용도**: JSON 직렬화/역직렬화
- **사용처**: OutboxEvent payload 직렬화

---

## 3. Domain 엔티티

### 3.1 User (사용자)

**경로:** `src/main/java/com/example/producer/domain/User.java`

**필드:**
- `id`: 사용자 고유 ID (자동 증가)
- `name`: 사용자 이름
- `email`: 이메일 주소 (유니크)
- `createdAt`: 생성 시간
- `updatedAt`: 수정 시간

**주요 어노테이션:**
```java
@Entity                        // JPA 엔티티
@Table(name = "users")         // 테이블명 지정
@Builder                       // 빌더 패턴
```

**생명주기 메서드:**
```java
@PrePersist
protected void onCreate() {
    createdAt = LocalDateTime.now();
    updatedAt = LocalDateTime.now();
}

@PreUpdate
protected void onUpdate() {
    updatedAt = LocalDateTime.now();
}
```

- `@PrePersist`: 저장 전 실행 (생성 시간 설정)
- `@PreUpdate`: 수정 전 실행 (수정 시간 갱신)

### 3.2 Order (주문)

**경로:** `src/main/java/com/example/producer/domain/Order.java`

**필드:**
- `id`: 주문 고유 ID
- `userId`: 주문한 사용자 ID
- `orderNumber`: 주문 번호 (유니크)
- `status`: 주문 상태 (기본값: "PENDING")
- `totalAmount`: 주문 총액
- `createdAt`: 생성 시간
- `updatedAt`: 수정 시간

**특징:**
- `status`는 기본값으로 "PENDING" 설정
- `orderNumber`는 유니크 제약으로 중복 방지

### 3.3 Product (상품)

**경로:** `src/main/java/com/example/producer/domain/Product.java`

**필드:**
- `id`: 상품 고유 ID
- `name`: 상품명
- `description`: 상품 설명
- `price`: 상품 가격
- `stock`: 재고 수량 (기본값: 0)
- `createdAt`: 생성 시간
- `updatedAt`: 수정 시간

**데이터 타입:**
- `price`: BigDecimal (정밀한 금액 계산)
- `stock`: Integer (재고 수량)

### 3.4 OutboxEvent (Outbox 이벤트)

**경로:** `src/main/java/com/example/producer/domain/OutboxEvent.java`

**핵심 엔티티로, Outbox Pattern의 중심입니다.**

**필드:**
- `id`: 레코드 ID (자동 증가)
- `eventId`: 이벤트 고유 ID (UUID, 멱등성 보장)
- `aggregateId`: 집합 루트 ID (user_id, order_id 등)
- `aggregateType`: 집합 타입 ("user", "order", "product")
- `eventType`: 이벤트 타입 ("created", "updated", "deleted")
- `payload`: 이벤트 페이로드 (JSON 형식)
- `occurredAt`: 이벤트 발생 시간
- `processed`: 처리 여부 (0: 미처리, 1: 처리 완료)

**디자인 포인트:**

1. **eventId (UUID)**: 멱등성 보장을 위한 고유 식별자
   ```java
   @Column(name = "event_id", unique = true, length = 36)
   private String eventId;
   ```

2. **aggregateType + aggregateId**: CDC 도구가 토픽을 결정하는 데 사용
   - 예: aggregateType="user" → "user-events" 토픽

3. **payload (JSON)**: 도메인 객체를 JSON으로 직렬화하여 저장
   ```java
   @Column(name = "payload", columnDefinition = "JSON")
   private String payload;
   ```

4. **processed 플래그**: CDC 처리 완료 여부 추적

**팩토리 메서드:**
```java
public static OutboxEvent of(String eventId, Long aggregateId, 
                             String aggregateType, String eventType, String payload) {
    return OutboxEvent.builder()
            .eventId(eventId)
            .aggregateId(aggregateId)
            .aggregateType(aggregateType)
            .eventType(eventType)
            .payload(payload)
            .occurredAt(LocalDateTime.now())
            .processed(false)
            .build();
}
```

---

## 4. Repository 레이어

### 4.1 Repository 인터페이스

모든 Repository는 `JpaRepository`를 상속받습니다.

**기본 메서드:**
- `save(T entity)`: 엔티티 저장
- `findById(ID id)`: ID로 조회
- `findAll()`: 전체 조회
- `delete(T entity)`: 엔티티 삭제

### 4.2 UserRepository

```java
@Repository
public interface UserRepository extends JpaRepository<User, Long> {
    Optional<User> findByEmail(String email);
}
```

**커스텀 메서드:**
- `findByEmail(String email)`: 이메일로 사용자 조회

### 4.3 OrderRepository

```java
@Repository
public interface OrderRepository extends JpaRepository<Order, Long> {
    Optional<Order> findByOrderNumber(String orderNumber);
    List<Order> findByUserId(Long userId);
}
```

**커스텀 메서드:**
- `findByOrderNumber(String orderNumber)`: 주문 번호로 조회
- `findByUserId(Long userId)`: 사용자 ID로 주문 목록 조회

**JPA 쿼리 메서드 규칙:**
- `findBy + 필드명`: 해당 필드로 조회
- 반환 타입: `Optional<T>` (단건), `List<T>` (다건)

---

## 5. Service 레이어

### 5.1 OutboxService (핵심 서비스)

**경로:** `src/main/java/com/example/producer/service/OutboxService.java`

**역할**: Outbox 이벤트 발행을 담당합니다.

**의존성:**
```java
private final OutboxEventRepository outboxEventRepository;
private final ObjectMapper objectMapper;
```

**핵심 메서드:**
```java
@Transactional
public void publishEvent(Long aggregateId, String aggregateType, 
                        String eventType, Object payload) {
    String eventId = UUID.randomUUID().toString();
    String payloadJson = objectMapper.writeValueAsString(payload);
    
    OutboxEvent event = OutboxEvent.of(
            eventId, aggregateId, aggregateType, eventType, payloadJson
    );
    
    outboxEventRepository.save(event);
}
```

**동작 흐름:**
1. UUID 생성
2. payload를 JSON으로 직렬화
3. OutboxEvent 생성
4. 데이터베이스에 저장

**트랜잭션 보장:**
- `@Transactional` 어노테이션으로 도메인 데이터와 이벤트가 동시에 커밋

### 5.2 UserService

**경로:** `src/main/java/com/example/producer/service/UserService.java`

**주요 메서드:**

#### createUser (사용자 생성)

```java
@Transactional
public User createUser(User user) {
    User savedUser = userRepository.save(user);
    
    outboxService.publishEvent(
            savedUser.getId(),
            "user",
            "created",
            savedUser
    );
    
    return savedUser;
}
```

**흐름:**
1. User 엔티티 저장
2. Outbox 이벤트 발행 (aggregateType="user", eventType="created")
3. 트랜잭션 커밋 (둘 다 저장됨)

#### updateUser (사용자 수정)

```java
@Transactional
public User updateUser(Long id, User user) {
    User existingUser = userRepository.findById(id)
            .orElseThrow(() -> new RuntimeException("User not found: id=" + id));
    
    existingUser.setName(user.getName());
    existingUser.setEmail(user.getEmail());
    
    User updatedUser = userRepository.save(existingUser);
    
    outboxService.publishEvent(
            updatedUser.getId(),
            "user",
            "updated",
            updatedUser
    );
    
    return updatedUser;
}
```

#### deleteUser (사용자 삭제)

```java
@Transactional
public void deleteUser(Long id) {
    User user = userRepository.findById(id)
            .orElseThrow(() -> new RuntimeException("User not found: id=" + id));
    
    // 삭제 전에 이벤트 발행
    outboxService.publishEvent(
            user.getId(),
            "user",
            "deleted",
            user
    );
    
    userRepository.delete(user);
}
```

**중요**: 삭제 **전에** 이벤트를 발행해야 삭제된 데이터도 이벤트에 포함됨

### 5.3 OrderService

**경로:** `src/main/java/com/example/producer/service/OrderService.java`

**주요 기능:**
- 주문 생성, 조회
- 주문 상태 변경
- 주문 취소

**상태 변경 예시:**
```java
@Transactional
public Order updateOrderStatus(Long id, String status) {
    Order order = orderRepository.findById(id)
            .orElseThrow(() -> new RuntimeException("Order not found: id=" + id));
    
    order.setStatus(status);
    Order updatedOrder = orderRepository.save(order);
    
    outboxService.publishEvent(
            updatedOrder.getId(),
            "order",
            "updated",
            updatedOrder
    );
    
    return updatedOrder;
}
```

### 5.4 ProductService

**경로:** `src/main/java/com/example/producer/service/ProductService.java`

OrderService와 유사한 구조로 동작합니다.

**특징:**
- 재고(stock) 관리
- 가격(price)은 BigDecimal 사용

---

## 6. Controller 레이어

### 6.1 REST API 설계 원칙

**URL 구조:**
- 리소스 중심: `/api/{resource}`
- 복수형 사용: `/api/users` (not `/api/user`)
- 동사 사용 금지: `/api/createUser` (부적절)

**HTTP 메서드:**
- `POST`: 생성
- `GET`: 조회
- `PUT`: 전체 수정
- `PATCH`: 부분 수정
- `DELETE`: 삭제

### 6.2 UserController

**경로:** `src/main/java/com/example/producer/controller/UserController.java`

**API 엔드포인트:**

| HTTP Method | URL | 설명 |
|-------------|-----|------|
| POST | `/api/users` | 사용자 생성 |
| GET | `/api/users/{id}` | 사용자 조회 |
| GET | `/api/users` | 전체 사용자 조회 |
| PUT | `/api/users/{id}` | 사용자 수정 |
| DELETE | `/api/users/{id}` | 사용자 삭제 |

**특징:**
```java
@RestController                    // REST 컨트롤러
@RequestMapping("/api/users")      // 기본 경로
@RequiredArgsConstructor           // 생성자 주입
public class UserController {
    private final UserService userService;
}
```

**응답 코드:**
- `201 Created`: POST 성공
- `200 OK`: GET, PUT 성공
- `204 No Content`: DELETE 성공

### 6.3 OrderController

**경로:** `src/main/java/com/example/producer/controller/OrderController.java`

**추가 엔드포인트:**
```java
@PatchMapping("/{id}/status")     // 주문 상태 변경
public ResponseEntity<Order> updateOrderStatus(
        @PathVariable Long id, 
        @RequestBody Map<String, String> statusUpdate) {
    String status = statusUpdate.get("status");
    Order updatedOrder = orderService.updateOrderStatus(id, status);
    return ResponseEntity.ok(updatedOrder);
}

@PostMapping("/{id}/cancel")      // 주문 취소
public ResponseEntity<Void> cancelOrder(@PathVariable Long id) {
    orderService.cancelOrder(id);
    return ResponseEntity.noContent().build();
}

@GetMapping("/user/{userId}")     // 사용자별 주문 조회
public ResponseEntity<List<Order>> getOrdersByUserId(@PathVariable Long userId) {
    List<Order> orders = orderService.getOrdersByUserId(userId);
    return ResponseEntity.ok(orders);
}
```

**RESTful 설계 포인트:**
- 동사 사용: `/cancel`, `/status` (하위 리소스로 취급)
- 필터링: `/user/{userId}` (서브 리소스)

### 6.4 ProductController

**경로:** `src/main/java/com/example/producer/controller/ProductController.java`

UserController와 동일한 CRUD 패턴을 따릅니다.

---

## 7. Configuration

### 7.1 JacksonConfig

**경로:** `src/main/java/com/example/producer/config/JacksonConfig.java`

**역할:** JSON 직렬화/역직렬화 설정

```java
@Configuration
public class JacksonConfig {
    
    @Bean
    public ObjectMapper objectMapper() {
        ObjectMapper mapper = new ObjectMapper();
        
        // Java 8 날짜/시간 타입 지원
        mapper.registerModule(new JavaTimeModule());
        
        // 날짜를 타임스탬프가 아닌 ISO-8601 형식으로 직렬화
        mapper.disable(SerializationFeature.WRITE_DATES_AS_TIMESTAMPS);
        
        return mapper;
    }
}
```

**설정 이유:**
- LocalDateTime을 ISO-8601 형식으로 직렬화
- 예: `"2024-01-01T10:00:00"` (not `1693564800000`)

**사용처:**
- OutboxEvent의 payload 직렬화
- REST API JSON 응답

### 7.2 ProducerApplication

**경로:** `src/main/java/com/example/producer/ProducerApplication.java`

```java
@SpringBootApplication
@EnableTransactionManagement
public class ProducerApplication {
    public static void main(String[] args) {
        SpringApplication.run(ProducerApplication.class, args);
    }
}
```

**어노테이션:**
- `@SpringBootApplication`: Spring Boot 자동 설정
- `@EnableTransactionManagement`: 선언적 트랜잭션 관리 활성화

---

## 8. 주요 의존 관계

### 8.1 의존성 구조도

```
Controller
    │
    │ depends on
    ▼
Service (OutboxService + DomainService)
    │
    │ depends on
    ▼
Repository
    │
    │ manages
    ▼
Domain Entity
```

### 8.2 의존성 주입 방식

**Constructor Injection 사용:**
```java
@RestController
@RequiredArgsConstructor  // Lombok이 생성자 자동 생성
public class UserController {
    private final UserService userService;  // final로 불변성 보장
}
```

**Lombok의 @RequiredArgsConstructor 동작:**
- final 필드에 대한 생성자 생성
- 생성자 주입 코드 불필요

**이전 방식 (수동):**
```java
@RestController
public class UserController {
    private final UserService userService;
    
    public UserController(UserService userService) {
        this.userService = userService;
    }
}
```

### 8.3 Service 간 의존성

```java
// UserService는 OutboxService를 의존
@Service
@RequiredArgsConstructor
public class UserService {
    private final UserRepository userRepository;
    private final OutboxService outboxService;  // 의존성
}
```

**트랜잭션 전파:**
- UserService의 `@Transactional` 메서드 호출
- 내부에서 OutboxService의 `@Transactional` 메서드 호출
- 같은 트랜잭션으로 처리됨

### 8.4 Repository 계층

```java
// 모든 Repository는 JpaRepository 상속
public interface UserRepository extends JpaRepository<User, Long> {
    // JpaRepository<User, Long>:
    // - User: 엔티티 타입
    // - Long: ID 타입
}
```

**제공 메서드 (JpaRepository 상속):**
- `save(S entity)`: 저장/수정
- `findById(ID id)`: ID로 조회
- `findAll()`: 전체 조회
- `delete(T entity)`: 삭제
- `count()`: 개수 조회

---

## 9. REST API 사용법

### 9.1 User API

#### 사용자 생성

**요청:**
```bash
curl -X POST http://localhost:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{
    "name": "홍길동",
    "email": "hong@example.com"
  }'
```

**응답:**
```json
{
  "id": 1,
  "name": "홍길동",
  "email": "hong@example.com",
  "createdAt": "2024-01-01T10:00:00",
  "updatedAt": "2024-01-01T10:00:00"
}
```

**HTTP 상태 코드:** 201 Created

#### 사용자 조회 (단건)

**요청:**
```bash
curl http://localhost:8080/api/users/1
```

**응답:**
```json
{
  "id": 1,
  "name": "홍길동",
  "email": "hong@example.com",
  "createdAt": "2024-01-01T10:00:00",
  "updatedAt": "2024-01-01T10:00:00"
}
```

**HTTP 상태 코드:** 200 OK

#### 전체 사용자 조회

**요청:**
```bash
curl http://localhost:8080/api/users
```

**응답:**
```json
[
  {
    "id": 1,
    "name": "홍길동",
    "email": "hong@example.com",
    "createdAt": "2024-01-01T10:00:00",
    "updatedAt": "2024-01-01T10:00:00"
  },
  {
    "id": 2,
    "name": "김철수",
    "email": "kim@example.com",
    "createdAt": "2024-01-01T10:05:00",
    "updatedAt": "2024-01-01T10:05:00"
  }
]
```

**HTTP 상태 코드:** 200 OK

#### 사용자 수정

**요청:**
```bash
curl -X PUT http://localhost:8080/api/users/1 \
  -H "Content-Type: application/json" \
  -d '{
    "name": "홍길동",
    "email": "hong_updated@example.com"
  }'
```

**응답:**
```json
{
  "id": 1,
  "name": "홍길동",
  "email": "hong_updated@example.com",
  "createdAt": "2024-01-01T10:00:00",
  "updatedAt": "2024-01-01T10:15:00"
}
```

**HTTP 상태 코드:** 200 OK

#### 사용자 삭제

**요청:**
```bash
curl -X DELETE http://localhost:8080/api/users/1
```

**응답:** (본문 없음)

**HTTP 상태 코드:** 204 No Content

### 9.2 Product API

#### 상품 생성

**요청:**
```bash
curl -X POST http://localhost:8080/api/products \
  -H "Content-Type: application/json" \
  -d '{
    "name": "노트북",
    "description": "고성능 노트북",
    "price": 1500000,
    "stock": 10
  }'
```

**응답:**
```json
{
  "id": 1,
  "name": "노트북",
  "description": "고성능 노트북",
  "price": 1500000,
  "stock": 10,
  "createdAt": "2024-01-01T10:00:00",
  "updatedAt": "2024-01-01T10:00:00"
}
```

**HTTP 상태 코드:** 201 Created

#### 상품 조회

**요청:**
```bash
curl http://localhost:8080/api/products/1
```

#### 상품 수정

**요청:**
```bash
curl -X PUT http://localhost:8080/api/products/1 \
  -H "Content-Type: application/json" \
  -d '{
    "name": "노트북 (업그레이드)",
    "description": "고성능 노트북 (신형)",
    "price": 1800000,
    "stock": 5
  }'
```

#### 상품 삭제

**요청:**
```bash
curl -X DELETE http://localhost:8080/api/products/1
```

### 9.3 Order API

#### 주문 생성

**요청:**
```bash
curl -X POST http://localhost:8080/api/orders \
  -H "Content-Type: application/json" \
  -d '{
    "userId": 1,
    "orderNumber": "ORD-2024-001",
    "status": "PENDING",
    "totalAmount": 1500000
  }'
```

**응답:**
```json
{
  "id": 1,
  "userId": 1,
  "orderNumber": "ORD-2024-001",
  "status": "PENDING",
  "totalAmount": 1500000,
  "createdAt": "2024-01-01T10:00:00",
  "updatedAt": "2024-01-01T10:00:00"
}
```

**HTTP 상태 코드:** 201 Created

#### 주문 상태 변경

**요청:**
```bash
curl -X PATCH http://localhost:8080/api/orders/1/status \
  -H "Content-Type: application/json" \
  -d '{
    "status": "CONFIRMED"
  }'
```

**응답:**
```json
{
  "id": 1,
  "userId": 1,
  "orderNumber": "ORD-2024-001",
  "status": "CONFIRMED",
  "totalAmount": 1500000,
  "createdAt": "2024-01-01T10:00:00",
  "updatedAt": "2024-01-01T10:30:00"
}
```

**HTTP 상태 코드:** 200 OK

#### 주문 취소

**요청:**
```bash
curl -X POST http://localhost:8080/api/orders/1/cancel
```

**응답:** (본문 없음)

**HTTP 상태 코드:** 204 No Content

#### 사용자별 주문 조회

**요청:**
```bash
curl http://localhost:8080/api/orders/user/1
```

**응답:**
```json
[
  {
    "id": 1,
    "userId": 1,
    "orderNumber": "ORD-2024-001",
    "status": "CONFIRMED",
    "totalAmount": 1500000,
    "createdAt": "2024-01-01T10:00:00",
    "updatedAt": "2024-01-01T10:30:00"
  }
]
```

### 9.4 jq를 사용한 출력 포맷팅

**설치:**
```bash
# macOS
brew install jq

# Ubuntu
apt-get install jq
```

**사용 예시:**
```bash
curl http://localhost:8080/api/users | jq .

# 특정 필드만 추출
curl http://localhost:8080/api/users/1 | jq .name

# 필터링
curl http://localhost:8080/api/users | jq '.[].email'
```

### 9.5 에러 응답

**404 Not Found:**
```bash
curl http://localhost:8080/api/users/999
```

**응답:**
```json
{
  "timestamp": "2024-01-01T10:00:00.000+00:00",
  "status": 404,
  "error": "Not Found",
  "message": "User not found: id=999",
  "path": "/api/users/999"
}
```

### 9.6 실습 시나리오

**시나리오 1: 전체 흐름 테스트**

```bash
# 1. 사용자 생성
curl -X POST http://localhost:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{"name": "홍길동", "email": "hong@example.com"}' | jq .

# 2. 상품 생성
curl -X POST http://localhost:8080/api/products \
  -H "Content-Type: application/json" \
  -d '{"name": "노트북", "description": "고성능 노트북", "price": 1500000, "stock": 10}' | jq .

# 3. 주문 생성
curl -X POST http://localhost:8080/api/orders \
  -H "Content-Type: application/json" \
  -d '{"userId": 1, "orderNumber": "ORD-001", "totalAmount": 1500000}' | jq .

# 4. 사용자 정보 수정
curl -X PUT http://localhost:8080/api/users/1 \
  -H "Content-Type: application/json" \
  -d '{"name": "홍길동", "email": "hong_updated@example.com"}' | jq .

# 5. Outbox 이벤트 확인 (SQL)
mysql -h 호스트 -u 사용자 -p 데이터베이스 -e "SELECT * FROM outbox_events ORDER BY id DESC;"
```

---

## 10. 핵심 개념 요약

### Outbox Pattern 흐름

1. **도메인 작업**: Controller → Service → Repository
2. **이벤트 발행**: Service에서 OutboxService.publishEvent() 호출
3. **트랜잭션 커밋**: 도메인 데이터와 이벤트가 동시에 저장
4. **CDC 연동**: Debezium 등이 outbox_events 변경 감지
5. **Kafka 발행**: CDC가 이벤트를 Kafka로 발행

### 트랜잭션 원자성

```java
@Transactional
public User createUser(User user) {
    User saved = repository.save(user);      // 1. User 저장
    outboxService.publishEvent(...);         // 2. Event 저장
    return saved;                            // 3. 트랜잭션 커밋
}
```

**보장 사항:**
- 둘 다 성공 → 커밋
- 하나라도 실패 → 롤백

### JPA 엔티티 생명주기

```
NEW → managed → detached
      ▲         |
      |         |
      └─────────┘
   persist()  remove()
```

- `@PrePersist`: persist() 전 실행
- `@PostPersist`: persist() 후 실행
- `@PreUpdate`: merge() 전 실행
- `@PostUpdate`: merge() 후 실행

---

## 11. 다음 단계

### 학습 심화

1. **테스트 코드 작성**: JUnit, MockMvc를 사용한 통합 테스트
2. **CDC 연동**: Debezium Connector 설정 및 Kafka 연결
3. **이벤트 처리**: OutboxEvent의 processed 플래그 관리
4. **에러 처리**: GlobalExceptionHandler 구현
5. **API 문서화**: Swagger/OpenAPI 설정

### 실무 적용

1. **확장성**: Redis를 활용한 캐싱
2. **모니터링**: Prometheus, Grafana 연동
3. **로깅**: ELK Stack 연동
4. **보안**: Jasypt를 사용한 필드 암호화

---

## 결론

이 가이드를 통해 다음을 이해했습니다:

- **Outbox Pattern의 구현 방법**
- **Spring Boot와 JPA의 활용**
- **RESTful API 설계 원칙**
- **트랜잭션 관리와 이벤트 발행**
- **레이어형 아키텍처의 구조**

위 내용을 바탕으로 실무에서 마이크로서비스 간 안전하고 일관된 이벤트 통신을 구현할 수 있습니다.

