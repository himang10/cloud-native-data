package com.example.consumer.listener;

import com.example.consumer.service.UserSummaryService;
import com.example.consumer.service.ProductSummaryService;
import com.example.consumer.service.OrderSummaryService;
import com.example.consumer.service.CustomerService;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.kafka.support.KafkaHeaders;
import org.springframework.messaging.handler.annotation.Header;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

/**
 * Debezium Outbox Event Kafka Listener
 * 
 * Debezium Outbox Event Router가 생성한 메시지를 수신합니다:
 * - outbox.user: aggregate_type='USER'인 이벤트
 * - outbox.product: aggregate_type='PRODUCT'인 이벤트  
 * - outbox.order: aggregate_type='ORDER'인 이벤트
 * 
 * Debezium이 outbox_events 테이블의 변경사항을 감지하여
 * aggregate_type 필드 값에 따라 적절한 토픽으로 라우팅합니다.
 * 메시지 헤더에는 event_id, event_type, aggregate_id, aggregate_type, occurred_at이 포함됩니다.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class OutboxEventListener {

    private final UserSummaryService userSummaryService;
    private final ProductSummaryService productSummaryService;
    private final OrderSummaryService orderSummaryService;
    private final CustomerService customerService;
    private final ObjectMapper objectMapper;

    /**
     * USER 이벤트 리스너 (Debezium Outbox Event Router)
     * 
     * Debezium이 outbox_events 테이블의 변경사항을 감지하여
     * aggregate_type='USER'인 이벤트를 outbox.user 토픽으로 라우팅합니다.
     */
    @KafkaListener(topics = "outbox.user", groupId = "outbox-consumer-group")
    @Transactional
    public void onUserEvent(
            @Payload String message,
            @Header(value = KafkaHeaders.RECEIVED_KEY, required = false) String key,
            @Header(value = "event_id", required = false) String eventId,
            @Header(value = "event_type", required = false) String eventType,
            @Header(value = "aggregate_id", required = false) String aggregateId,
            @Header(value = "aggregate_type", required = false) String aggregateType,
            @Header(value = "occurred_at", required = false) String occurredAt,
            Acknowledgment acknowledgment) {
        
        try {
            log.info("Received Debezium USER event: eventId={}, eventType={}, aggregateId={}, aggregateType={}, key={}, occurredAt={}", 
                    eventId, eventType, aggregateId, aggregateType, key, occurredAt);
            log.debug("Debezium message payload: {}", message);

            JsonNode payload = objectMapper.readTree(message);
            
            // Customer Service와 UserSummary Service를 단일 트랜잭션으로 처리
            // Customer 테이블에 데이터 저장 (occurredAt 포함)
            customerService.processUserEvent(eventId, eventType, occurredAt, payload);
            
            // UserSummary 테이블에도 함께 저장 (occurredAt 포함)
            userSummaryService.processUserEvent(eventId, eventType, occurredAt, payload);
            
            // 수동 커밋
            if (acknowledgment != null) {
                acknowledgment.acknowledge();
            }
            
            log.info("Debezium USER event processed successfully: eventId={}", eventId);
            
        } catch (Exception e) {
            log.error("Failed to process Debezium USER event: eventId={}, error={}", eventId, e.getMessage(), e);
            // 에러 발생 시 재처리를 위해 acknowledge하지 않음
            throw new RuntimeException("Failed to process Debezium USER event", e);
        }
    }

    /**
     * PRODUCT 이벤트 리스너 (Debezium Outbox Event Router)
     * 
     * Debezium이 outbox_events 테이블의 변경사항을 감지하여
     * aggregate_type='PRODUCT'인 이벤트를 outbox.product 토픽으로 라우팅합니다.
     */
    @KafkaListener(topics = "outbox.product", groupId = "outbox-consumer-group")
    public void onProductEvent(
            @Payload String message,
            @Header(value = KafkaHeaders.RECEIVED_KEY, required = false) String key,
            @Header(value = "event_id", required = false) String eventId,
            @Header(value = "event_type", required = false) String eventType,
            @Header(value = "aggregate_id", required = false) String aggregateId,
            @Header(value = "aggregate_type", required = false) String aggregateType,
            @Header(value = "occurred_at", required = false) String occurredAt,
            Acknowledgment acknowledgment) {
        
        try {
            log.info("Received Debezium PRODUCT event: eventId={}, eventType={}, aggregateId={}, aggregateType={}, key={}, occurredAt={}", 
                    eventId, eventType, aggregateId, aggregateType, key, occurredAt);
            log.debug("Debezium message payload: {}", message);

            JsonNode payload = objectMapper.readTree(message);
            
            productSummaryService.processProductEvent(eventId, eventType, occurredAt, payload);
            
            if (acknowledgment != null) {
                acknowledgment.acknowledge();
            }
            
            log.info("Debezium PRODUCT event processed successfully: eventId={}", eventId);
            
        } catch (Exception e) {
            log.error("Failed to process Debezium PRODUCT event: eventId={}, error={}", eventId, e.getMessage(), e);
            throw new RuntimeException("Failed to process Debezium PRODUCT event", e);
        }
    }

    /**
     * ORDER 이벤트 리스너 (Debezium Outbox Event Router)
     * 
     * Debezium이 outbox_events 테이블의 변경사항을 감지하여
     * aggregate_type='ORDER'인 이벤트를 outbox.order 토픽으로 라우팅합니다.
     */
    @KafkaListener(topics = "outbox.order", groupId = "outbox-consumer-group")
    public void onOrderEvent(
            @Payload String message,
            @Header(value = KafkaHeaders.RECEIVED_KEY, required = false) String key,
            @Header(value = "event_id", required = false) String eventId,
            @Header(value = "event_type", required = false) String eventType,
            @Header(value = "aggregate_id", required = false) String aggregateId,
            @Header(value = "aggregate_type", required = false) String aggregateType,
            @Header(value = "occurred_at", required = false) String occurredAt,
            Acknowledgment acknowledgment) {
        
        try {
            log.info("Received Debezium ORDER event: eventId={}, eventType={}, aggregateId={}, aggregateType={}, key={}, occurredAt={}", 
                    eventId, eventType, aggregateId, aggregateType, key, occurredAt);
            log.debug("Debezium message payload: {}", message);

            JsonNode payload = objectMapper.readTree(message);
            
            orderSummaryService.processOrderEvent(eventId, eventType, occurredAt, payload);
            
            if (acknowledgment != null) {
                acknowledgment.acknowledge();
            }
            
            log.info("Debezium ORDER event processed successfully: eventId={}", eventId);
            
        } catch (Exception e) {
            log.error("Failed to process Debezium ORDER event: eventId={}, error={}", eventId, e.getMessage(), e);
            throw new RuntimeException("Failed to process Debezium ORDER event", e);
        }
    }
}

