# Outbox Schema Verification

## Java Entity와 DB 테이블 구조 일치 확인

### ✅ Java Entity (OutboxEvent.java)

```java
@Entity
@Table(name = "outbox_events")
public class OutboxEvent {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;                    // BIGINT AUTO_INCREMENT PRIMARY KEY
    
    @Column(name = "event_id", nullable = false, unique = true, length = 36, columnDefinition = "CHAR(36)")
    private String eventId;             // CHAR(36) UNIQUE
    
    @Column(name = "aggregate_id", nullable = false)
    private Long aggregateId;           // BIGINT NOT NULL
    
    @Column(name = "aggregate_type", nullable = false, length = 255)
    private String aggregateType;       // VARCHAR(255) NOT NULL
    
    @Column(name = "event_type", nullable = false, length = 255)
    private String eventType;           // VARCHAR(255) NOT NULL
    
    @Column(name = "payload", nullable = false, columnDefinition = "JSON")
    private String payload;             // JSON NOT NULL
    
    @Column(name = "occurred_at", nullable = false, columnDefinition = "TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3)")
    private LocalDateTime occurredAt;   // TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3)
    
    @Column(name = "processed", nullable = false, columnDefinition = "TINYINT(1) DEFAULT 0")
    @Builder.Default
    private Boolean processed = false;  // TINYINT(1) DEFAULT 0
}
```

### ✅ DB 테이블 구조 (MariaDB)

```sql
CREATE TABLE outbox_events (
    id             BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_id       CHAR(36) NOT NULL UNIQUE,
    aggregate_id   BIGINT NOT NULL,
    aggregate_type VARCHAR(255) NOT NULL,
    event_type     VARCHAR(255) NOT NULL,
    payload        JSON NOT NULL,
    occurred_at    TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3) NOT NULL,
    processed      TINYINT(1) DEFAULT 0 NOT NULL,
    INDEX idx_aggregate_type (aggregate_type),
    INDEX idx_occurred_at (occurred_at),
    INDEX idx_processed (processed)
);
```

### 🔍 필드별 매칭 확인

| 필드명 | Java 타입 | DB 타입 | 제약조건 | 일치 여부 |
|--------|-----------|---------|----------|-----------|
| id | Long | bigint(20) | PRI, AUTO_INCREMENT | ✅ 완벽 일치 |
| event_id | String (36) | char(36) | UNI, NOT NULL | ✅ 완벽 일치 |
| aggregate_id | Long | bigint(20) | NOT NULL | ✅ 완벽 일치 |
| aggregate_type | String (255) | varchar(255) | NOT NULL, MUL | ✅ 완벽 일치 |
| event_type | String (255) | varchar(255) | NOT NULL | ✅ 완벽 일치 |
| payload | String (JSON) | longtext (JSON) | NOT NULL | ✅ 완벽 일치 |
| occurred_at | LocalDateTime | timestamp(3) | NOT NULL, MUL, DEFAULT | ✅ 완벽 일치 |
| processed | Boolean | tinyint(1) | NOT NULL, MUL, DEFAULT 0 | ✅ 완벽 일치 |

### 📊 샘플 데이터 확인

현재 테이블에 저장된 5개의 샘플 이벤트:

```
id=1, event_id=612dc7c4-..., aggregate_type=USER,    aggregate_id=1,    event_type=created, processed=0
id=2, event_id=612dd00c-..., aggregate_type=USER,    aggregate_id=2,    event_type=created, processed=0
id=3, event_id=612dd3dd-..., aggregate_type=ORDER,   aggregate_id=1001, event_type=created, processed=0
id=4, event_id=612dd616-..., aggregate_type=ORDER,   aggregate_id=1002, event_type=created, processed=0
id=5, event_id=612dd6a9-..., aggregate_type=PRODUCT, aggregate_id=101,  event_type=created, processed=0
```

### ✅ 주요 개선 사항

1. **Primary Key 수정**: `event_id` → `id` (JPA @Id 매칭)
2. **aggregate_id 타입 변경**: `VARCHAR(100)` → `BIGINT` (Long 타입 매칭)
3. **processed 필드 추가**: `processed_at TIMESTAMP(6)` → `processed TINYINT(1)` (Boolean 매칭)
4. **타임스탬프 정밀도**: `TIMESTAMP(6)` → `TIMESTAMP(3)` (밀리초 정밀도, LocalDateTime 매칭)
5. **VARCHAR 길이 확장**: `VARCHAR(100)` → `VARCHAR(255)` (JPA 기본값 매칭)
6. **aggregate_type 대문자화**: `user` → `USER`, `order` → `ORDER`, `product` → `PRODUCT`

### 🎯 Debezium Outbox Pattern 호환성

- ✅ **event_id**: UUID 형식, 멱등성 보장
- ✅ **aggregate_id**: BIGINT로 Kafka 메시지 키 생성
- ✅ **aggregate_type**: 대문자 형식으로 토픽 라우팅 (`outbox.USER`, `outbox.ORDER`, `outbox.PRODUCT`)
- ✅ **payload**: JSON 형식으로 CloudEvents 호환
- ✅ **processed**: Boolean 타입으로 이벤트 처리 상태 관리

### 🔄 Connector 재시작 필요 여부

스키마가 변경되었으므로 기존 커넥터를 재등록해야 합니다:

```bash
# 기존 커넥터 삭제
./delete-connector.sh mariadb-outbox-connector

# 새 스키마로 커넥터 재등록
./register-connector.sh mariadb-outbox-connector.json
```

### 📝 검증 날짜

- **생성일**: 2025-11-15 16:01:43.280
- **검증 완료**: 테이블 구조와 Java Entity가 100% 일치함
