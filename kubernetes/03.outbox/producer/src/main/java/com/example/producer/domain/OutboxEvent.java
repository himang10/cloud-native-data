package com.example.producer.domain;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * Outbox Event 엔티티
 * 
 * Debezium Outbox Pattern을 위한 이벤트 저장소
 * Debezium이 이 테이블의 변경사항을 CDC하여 Kafka로 전송합니다.
 */
@Entity
@Table(name = "outbox_events")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class OutboxEvent {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    /**
     * 이벤트 고유 ID (UUID)
     * 멱등성 보장을 위해 사용
     */
    @Column(name = "event_id", nullable = false, unique = true, length = 36, columnDefinition = "CHAR(36)")
    private String eventId;

    /**
     * 집합 루트 ID (예: user_id, order_id, product_id)
     */
    @Column(name = "aggregate_id", nullable = false)
    private Long aggregateId;

    /**
     * 집합 타입 (예: USER, ORDER, PRODUCT)
     * Debezium Outbox Router가 이 값으로 토픽을 결정
     */
    @Column(name = "aggregate_type", nullable = false, length = 255)
    private String aggregateType;

    /**
     * 이벤트 타입 (예: created, updated, deleted)
     */
    @Column(name = "event_type", nullable = false, length = 255)
    private String eventType;

    /**
     * 이벤트 페이로드 (JSON 형식)
     * 실제 도메인 데이터를 JSON으로 직렬화하여 저장
     */
    @Column(name = "payload", nullable = false, columnDefinition = "JSON")
    private String payload;

    /**
     * 이벤트 발생 시간 (밀리초 정밀도)
     */
    @Column(name = "occurred_at", nullable = false, columnDefinition = "TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3)")
    private LocalDateTime occurredAt;

    /**
     * 처리 여부
     * 0: 미처리, 1: 처리 완료
     */
    @Column(name = "processed", nullable = false, columnDefinition = "TINYINT(1) DEFAULT 0")
    @Builder.Default
    private Boolean processed = false;

    @PrePersist
    protected void onCreate() {
        if (occurredAt == null) {
            occurredAt = LocalDateTime.now();
        }
    }

    /**
     * Outbox Event 생성 팩토리 메서드
     */
    public static OutboxEvent of(String eventId, Long aggregateId, String aggregateType, 
                                  String eventType, String payload) {
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
}

