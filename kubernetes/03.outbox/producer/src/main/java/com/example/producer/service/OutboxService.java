package com.example.producer.service;

import com.example.producer.domain.OutboxEvent;
import com.example.producer.domain.User;
import com.example.producer.repository.OutboxEventRepository;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

/**
 * Outbox Event 관리 서비스
 * 
 * 도메인 이벤트를 Outbox 테이블에 저장합니다.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class OutboxService {

    private final OutboxEventRepository outboxEventRepository;
    private final ObjectMapper objectMapper;

    /**
     * Outbox 이벤트 발행
     * 
     * @param aggregateId 집합 루트 ID
     * @param aggregateType 집합 타입 (USER, ORDER, PRODUCT)
     * @param eventType 이벤트 타입 (created, updated, deleted)
     * @param payload 도메인 객체
     */
    @Transactional
    public void publishEvent(Long aggregateId, String aggregateType, String eventType, Object payload) {
        try {
            String eventId = UUID.randomUUID().toString();
            
            // User 객체의 경우 필요한 필드만 추출하여 JSON 생성
            String payloadJson;
            if (payload instanceof User) {
                User user = (User) payload;
                payloadJson = String.format(
                    "{\"id\":%d,\"name\":\"%s\",\"email\":\"%s\"}",
                    user.getId() != null ? user.getId() : 0,
                    user.getName() != null ? user.getName() : "",
                    user.getEmail() != null ? user.getEmail() : ""
                );
            } else {
                payloadJson = objectMapper.writeValueAsString(payload);
            }

            OutboxEvent event = OutboxEvent.of(
                    eventId,
                    aggregateId,
                    aggregateType,
                    eventType,
                    payloadJson
            );

            outboxEventRepository.save(event);
            
            log.info("Outbox event published: eventId={}, aggregateType={}, eventType={}, aggregateId={}", 
                    eventId, aggregateType, eventType, aggregateId);
        } catch (Exception e) {
            log.error("Failed to publish outbox event: aggregateType={}, eventType={}, aggregateId={}", 
                    aggregateType, eventType, aggregateId, e);
            throw new RuntimeException("Failed to publish outbox event", e);
        }
    }
}

