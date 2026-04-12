package com.example.consumer.service;

import com.example.consumer.domain.OrderSummary;
import com.example.consumer.repository.OrderSummaryRepository;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;

/**
 * Order Summary 서비스
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class OrderSummaryService {

    private final OrderSummaryRepository repository;
    private static final DateTimeFormatter FORMATTER = DateTimeFormatter.ISO_DATE_TIME;

    @Transactional
    public void processOrderEvent(String eventId, String eventType, String occurredAt, JsonNode payload) {
        log.debug("Processing ORDER event: eventId={}, eventType={}", eventId, eventType);

        if (repository.findByEventId(eventId).isPresent()) {
            log.info("ORDER event already processed (idempotency): eventId={}", eventId);
            return;
        }

        Long orderId = payload.get("id").asLong();
        Long userId = payload.get("userId").asLong();
        String orderNumber = payload.get("orderNumber").asText();
        String status = payload.get("status").asText();
        BigDecimal totalAmount = new BigDecimal(payload.get("totalAmount").asText());
        
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

        OrderSummary summary = repository.findById(orderId)
                .orElse(OrderSummary.builder()
                        .orderId(orderId)
                        .build());

        summary.setEventId(eventId);
        summary.setUserId(userId);
        summary.setOrderNumber(orderNumber);
        summary.setStatus(status);
        summary.setTotalAmount(totalAmount);
        summary.setEventType(eventType);
        
        // CREATED 이벤트일 때만 source_created_at 설정
        if (!repository.existsById(orderId) || "created".equals(eventType)) {
            summary.setSourceCreatedAt(sourceCreatedAt);
        }
        // UPDATE 이벤트일 때 source_updated_at만 업데이트
        if (!"created".equals(eventType)) {
            summary.setSourceUpdatedAt(sourceUpdatedAt);
        }

        repository.save(summary);
        
        log.info("ORDER summary saved: orderId={}, eventType={}, eventId={}", orderId, eventType, eventId);
    }

    @Transactional(readOnly = true)
    public OrderSummary getOrderSummary(Long orderId) {
        return repository.findById(orderId)
                .orElseThrow(() -> new RuntimeException("Order summary not found: orderId=" + orderId));
    }

    @Transactional(readOnly = true)
    public List<OrderSummary> getOrderSummariesByUserId(Long userId) {
        return repository.findByUserId(userId);
    }

    @Transactional(readOnly = true)
    public List<OrderSummary> getAllOrderSummaries() {
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

