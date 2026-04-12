package com.example.consumer.service;

import com.example.consumer.entity.Customer;
import com.example.consumer.repository.CustomerRepository;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Optional;

/**
 * Customer Service
 * 
 * Customer Entity의 CRUD 작업을 처리하는 Service
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class CustomerService {

    private final CustomerRepository customerRepository;

    /**
     * User 이벤트를 처리하여 Customer를 저장 또는 업데이트
     * 
     * @param eventId 이벤트 ID
     * @param eventType 이벤트 타입 (created, updated, deleted)
     * @param occurredAt 이벤트 발생 시간
     * @param payload 이벤트 페이로드
     */
    @Transactional
    public void processUserEvent(String eventId, String eventType, String occurredAt, JsonNode payload) {
        try {
            log.info("Processing user event: eventId={}, eventType={}, occurredAt={}", eventId, eventType, occurredAt);
            
            Long customerId = payload.get("id").asLong();
            String name = payload.get("name").asText();
            String email = payload.get("email").asText();
            
            log.debug("Customer data: customerId={}, name={}, email={}", customerId, name, email);
            
            // DELETE 처리
            if ("deleted".equals(eventType)) {
                deleteCustomer(customerId);
                log.info("Customer deleted: customerId={}, eventId={}", customerId, eventId);
                return;
            }
            
            Optional<Customer> existingCustomer = customerRepository.findByCustomerId(customerId);
            
            if (existingCustomer.isPresent()) {
                // UPDATE 처리
                Customer customer = existingCustomer.get();
                customer.setName(name);
                customer.setEmail(email);
                // source_updated_at 업데이트
                if (occurredAt != null && !occurredAt.isEmpty()) {
                    customer.setSourceUpdatedAt(parseOccurredAt(occurredAt));
                }
                customerRepository.save(customer);
                log.info("Customer updated: customerId={}", customerId);
            } else {
                // CREATE 처리
                Customer customer = Customer.builder()
                        .customerId(customerId)
                        .name(name)
                        .email(email)
                        .build();
                // source_created_at 설정
                if (occurredAt != null && !occurredAt.isEmpty()) {
                    customer.setSourceCreatedAt(parseOccurredAt(occurredAt));
                    customer.setSourceUpdatedAt(parseOccurredAt(occurredAt));
                }
                customerRepository.save(customer);
                log.info("Customer created: customerId={}", customerId);
            }
            
            log.info("Customer event processed successfully: eventId={}, customerId={}", eventId, customerId);
            
        } catch (Exception e) {
            log.error("Failed to process customer event: eventId={}, error={}", eventId, e.getMessage(), e);
            throw new RuntimeException("Failed to process customer event", e);
        }
    }
    
    /**
     * occurredAt 문자열을 LocalDateTime으로 파싱
     */
    private java.time.LocalDateTime parseOccurredAt(String occurredAt) {
        if (occurredAt == null || occurredAt.isEmpty()) {
            return null;
        }
        try {
            return java.time.LocalDateTime.parse(occurredAt.replace("Z", ""));
        } catch (Exception e) {
            log.warn("Failed to parse occurredAt: {}", occurredAt);
            return null;
        }
    }

    /**
     * Customer ID로 조회
     */
    @Transactional(readOnly = true)
    public Optional<Customer> getCustomerByCustomerId(Long customerId) {
        return customerRepository.findByCustomerId(customerId);
    }

    /**
     * Customer Email로 조회
     */
    @Transactional(readOnly = true)
    public Optional<Customer> getCustomerByEmail(String email) {
        return customerRepository.findByEmail(email);
    }

    /**
     * 모든 Customer 조회
     */
    @Transactional(readOnly = true)
    public Iterable<Customer> getAllCustomers() {
        return customerRepository.findAll();
    }

    /**
     * Customer 삭제
     */
    @Transactional
    public void deleteCustomer(Long customerId) {
        Optional<Customer> customer = customerRepository.findByCustomerId(customerId);
        if (customer.isPresent()) {
            customerRepository.delete(customer.get());
            log.info("Customer deleted: customerId={}", customerId);
        } else {
            log.warn("Customer not found for deletion: customerId={}", customerId);
        }
    }
}

