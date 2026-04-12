package com.example.consumer.domain;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Order Summary 엔티티 (PostgreSQL에 저장)
 */
@Entity
@Table(name = "order_summary", indexes = {
    @Index(name = "idx_order_event_id", columnList = "event_id", unique = true),
    @Index(name = "idx_order_user_id", columnList = "user_id")
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class OrderSummary {

    @Id
    @Column(name = "order_id")
    private Long orderId;

    @Column(name = "event_id", nullable = false, unique = true, length = 36)
    private String eventId;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "order_number", nullable = false, length = 50)
    private String orderNumber;

    @Column(nullable = false, length = 50)
    private String status;

    @Column(name = "total_amount", nullable = false, precision = 10, scale = 2)
    private BigDecimal totalAmount;

    @Column(name = "event_type", length = 50)
    private String eventType;

    @Column(name = "source_created_at")
    private LocalDateTime sourceCreatedAt;

    @Column(name = "source_updated_at")
    private LocalDateTime sourceUpdatedAt;

    @Column(name = "consumed_at", nullable = false)
    private LocalDateTime consumedAt;

    @Column(name = "last_modified_at", nullable = false)
    private LocalDateTime lastModifiedAt;

    @PrePersist
    @PreUpdate
    protected void onUpdate() {
        lastModifiedAt = LocalDateTime.now();
        if (consumedAt == null) {
            consumedAt = LocalDateTime.now();
        }
    }
}

