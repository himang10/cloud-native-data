package com.example.consumer.domain;

import jakarta.persistence.*;
import lombok.*;

import java.time.LocalDateTime;

/**
 * User Summary 엔티티 (PostgreSQL에 저장)
 * 
 * MariaDB의 User 이벤트를 수신하여 저장하는 읽기 전용 모델
 */
@Entity
@Table(name = "user_summary", indexes = {
    @Index(name = "idx_user_event_id", columnList = "event_id", unique = true)
})
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class UserSummary {

    @Id
    @Column(name = "user_id")
    private Long userId;

    @Column(name = "event_id", nullable = false, unique = true, length = 36)
    private String eventId;  // 멱등성 보장용

    @Column(nullable = false, length = 100)
    private String name;

    @Column(nullable = false, length = 100)
    private String email;

    @Column(name = "event_type", length = 50)
    private String eventType;  // created, updated, deleted

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

