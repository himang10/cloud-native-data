package com.example.consumer.domain;

import jakarta.persistence.*;
import lombok.*;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Product Summary 엔티티 (PostgreSQL에 저장)
 */
@Entity
@Table(name = "product_summary", indexes = {
    @Index(name = "idx_product_event_id", columnList = "event_id", unique = true)
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class ProductSummary {

    @Id
    @Column(name = "product_id")
    private Long productId;

    @Column(name = "event_id", nullable = false, unique = true, length = 36)
    private String eventId;

    @Column(nullable = false, length = 200)
    private String name;

    @Column(columnDefinition = "TEXT")
    private String description;

    @Column(nullable = false, precision = 10, scale = 2)
    private BigDecimal price;

    @Column(nullable = false)
    private Integer stock;

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

