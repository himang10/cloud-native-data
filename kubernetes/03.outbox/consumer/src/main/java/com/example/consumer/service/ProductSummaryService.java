package com.example.consumer.service;

import com.example.consumer.domain.ProductSummary;
import com.example.consumer.repository.ProductSummaryRepository;
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
 * Product Summary 서비스
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ProductSummaryService {

    private final ProductSummaryRepository repository;
    private static final DateTimeFormatter FORMATTER = DateTimeFormatter.ISO_DATE_TIME;

    @Transactional
    public void processProductEvent(String eventId, String eventType, String occurredAt, JsonNode payload) {
        log.debug("Processing PRODUCT event: eventId={}, eventType={}", eventId, eventType);

        if (repository.findByEventId(eventId).isPresent()) {
            log.info("PRODUCT event already processed (idempotency): eventId={}", eventId);
            return;
        }

        Long productId = payload.get("id").asLong();
        String name = payload.get("name").asText();
        String description = payload.has("description") ? payload.get("description").asText() : null;
        BigDecimal price = new BigDecimal(payload.get("price").asText());
        Integer stock = payload.get("stock").asInt();
        
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

        if ("deleted".equals(eventType)) {
            repository.deleteById(productId);
            log.info("PRODUCT deleted: productId={}, eventId={}", productId, eventId);
            return;
        }

        ProductSummary summary = repository.findById(productId)
                .orElse(ProductSummary.builder()
                        .productId(productId)
                        .build());

        summary.setEventId(eventId);
        summary.setName(name);
        summary.setDescription(description);
        summary.setPrice(price);
        summary.setStock(stock);
        summary.setEventType(eventType);
        
        // CREATED 이벤트일 때만 source_created_at 설정
        if (!repository.existsById(productId) || "created".equals(eventType)) {
            summary.setSourceCreatedAt(sourceCreatedAt);
        }
        // UPDATE 이벤트일 때 source_updated_at만 업데이트
        if (!"created".equals(eventType)) {
            summary.setSourceUpdatedAt(sourceUpdatedAt);
        }

        repository.save(summary);
        
        log.info("PRODUCT summary saved: productId={}, eventType={}, eventId={}", productId, eventType, eventId);
    }

    @Transactional(readOnly = true)
    public ProductSummary getProductSummary(Long productId) {
        return repository.findById(productId)
                .orElseThrow(() -> new RuntimeException("Product summary not found: productId=" + productId));
    }

    @Transactional(readOnly = true)
    public List<ProductSummary> getAllProductSummaries() {
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

