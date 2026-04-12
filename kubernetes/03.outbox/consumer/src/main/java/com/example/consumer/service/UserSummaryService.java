package com.example.consumer.service;

import com.example.consumer.domain.UserSummary;
import com.example.consumer.repository.UserSummaryRepository;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * User Summary 서비스
 * 
 * Kafka에서 수신한 User 이벤트를 PostgreSQL에 UPSERT합니다.
 * event_id를 이용한 멱등성을 보장합니다.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class UserSummaryService {

    private final UserSummaryRepository repository;
    private static final DateTimeFormatter FORMATTER = DateTimeFormatter.ISO_DATE_TIME;

    /**
     * User 이벤트 처리 (UPSERT)
     */
    @Transactional
    public void processUserEvent(String eventId, String eventType, String occurredAt, JsonNode payload) {
        log.debug("Processing USER event: eventId={}, eventType={}", eventId, eventType);

        // 멱등성 체크: 동일한 eventId가 이미 처리되었는지 확인
        if (repository.findByEventId(eventId).isPresent()) {
            log.info("USER event already processed (idempotency): eventId={}", eventId);
            return;
        }

        Long userId = payload.get("id").asLong();
        String name = payload.get("name").asText();
        String email = payload.get("email").asText();
        
        // source_created_at과 source_updated_at 설정
        // occurredAt 헤더 값을 사용
        LocalDateTime sourceCreatedAt = null;
        LocalDateTime sourceUpdatedAt = null;
        if (occurredAt != null && !occurredAt.isEmpty()) {
            try {
                sourceCreatedAt = LocalDateTime.parse(occurredAt.replace("Z", ""));
                sourceUpdatedAt = LocalDateTime.parse(occurredAt.replace("Z", ""));
            } catch (Exception e) {
                log.warn("Failed to parse occurredAt: {}", occurredAt);
            }
        }

        // DELETED 이벤트인 경우 레코드 삭제
        if ("deleted".equals(eventType)) {
            repository.deleteById(userId);
            log.info("USER deleted: userId={}, eventId={}", userId, eventId);
            return;
        }

        // UPSERT 처리
        UserSummary summary = repository.findById(userId)
                .orElse(UserSummary.builder()
                        .userId(userId)
                        .build());

        summary.setEventId(eventId);
        summary.setName(name);
        summary.setEmail(email);
        summary.setEventType(eventType);
        
        // CREATED 이벤트일 때만 source_created_at 설정
        if (!repository.existsById(userId) || "created".equals(eventType)) {
            summary.setSourceCreatedAt(sourceCreatedAt);
        }
        // UPDATE 이벤트일 때 source_updated_at만 업데이트
        if (!"updated".equals(eventType)) {
            summary.setSourceUpdatedAt(sourceUpdatedAt);
        }

        repository.save(summary);
        
        log.info("USER summary saved: userId={}, eventType={}, eventId={}", userId, eventType, eventId);
    }

    @Transactional(readOnly = true)
    public UserSummary getUserSummary(Long userId) {
        return repository.findById(userId)
                .orElseThrow(() -> new RuntimeException("User summary not found: userId=" + userId));
    }

    @Transactional(readOnly = true)
    public List<UserSummary> getAllUserSummaries() {
        return repository.findAll();
    }

    private LocalDateTime parseDateTime(JsonNode node) {
        if (node == null || node.isNull()) {
            return null;
        }
        try {
            return LocalDateTime.parse(node.asText(), FORMATTER);
        } catch (Exception e) {
            log.warn("Failed to parse datetime: {}", node.asText());
            return null;
        }
    }
}

