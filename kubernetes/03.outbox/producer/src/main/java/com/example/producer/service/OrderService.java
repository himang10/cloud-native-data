package com.example.producer.service;

import com.example.producer.domain.Order;
import com.example.producer.repository.OrderRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * Order 도메인 서비스
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class OrderService {

    private final OrderRepository orderRepository;
    private final OutboxService outboxService;

    /**
     * 주문 생성
     */
    @Transactional
    public Order createOrder(Order order) {
        log.info("Creating order: orderNumber={}, userId={}", order.getOrderNumber(), order.getUserId());
        
        Order savedOrder = orderRepository.save(order);
        
        // Outbox 이벤트 발행
        outboxService.publishEvent(
                savedOrder.getId(),
                "order",
                "created",
                savedOrder
        );
        
        log.info("Order created successfully: id={}, orderNumber={}", savedOrder.getId(), savedOrder.getOrderNumber());
        return savedOrder;
    }

    /**
     * 주문 상태 변경
     */
    @Transactional
    public Order updateOrderStatus(Long id, String status) {
        log.info("Updating order status: id={}, status={}", id, status);
        
        Order order = orderRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Order not found: id=" + id));
        
        order.setStatus(status);
        Order updatedOrder = orderRepository.save(order);
        
        // Outbox 이벤트 발행
        outboxService.publishEvent(
                updatedOrder.getId(),
                "order",
                "updated",
                updatedOrder
        );
        
        log.info("Order status updated successfully: id={}, status={}", updatedOrder.getId(), status);
        return updatedOrder;
    }

    /**
     * 주문 취소
     */
    @Transactional
    public void cancelOrder(Long id) {
        log.info("Canceling order: id={}", id);
        
        Order order = orderRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Order not found: id=" + id));
        
        order.setStatus("cancelled");
        orderRepository.save(order);
        
        // Outbox 이벤트 발행
        outboxService.publishEvent(
                order.getId(),
                "order",
                "cancelled",
                order
        );
        
        log.info("Order cancelled successfully: id={}", id);
    }

    /**
     * 주문 조회
     */
    @Transactional(readOnly = true)
    public Order getOrder(Long id) {
        return orderRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Order not found: id=" + id));
    }

    /**
     * 사용자별 주문 조회
     */
    @Transactional(readOnly = true)
    public List<Order> getOrdersByUserId(Long userId) {
        return orderRepository.findByUserId(userId);
    }

    /**
     * 전체 주문 조회
     */
    @Transactional(readOnly = true)
    public List<Order> getAllOrders() {
        return orderRepository.findAll();
    }
}

