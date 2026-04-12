package com.example.producer.service;

import com.example.producer.domain.OrderItem;
import com.example.producer.repository.OrderItemRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * OrderItem 도메인 서비스
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class OrderItemService {

    private final OrderItemRepository orderItemRepository;

    /**
     * 주문 항목 생성
     */
    @Transactional
    public OrderItem createOrderItem(OrderItem orderItem) {
        log.info("Creating order item: orderId={}, productId={}", orderItem.getOrderId(), orderItem.getProductId());
        OrderItem savedOrderItem = orderItemRepository.save(orderItem);
        log.info("Order item created successfully: id={}", savedOrderItem.getId());
        return savedOrderItem;
    }

    /**
     * 주문별 항목 조회
     */
    @Transactional(readOnly = true)
    public List<OrderItem> getOrderItemsByOrderId(Long orderId) {
        return orderItemRepository.findByOrderId(orderId);
    }

    /**
     * 상품별 주문 항목 조회
     */
    @Transactional(readOnly = true)
    public List<OrderItem> getOrderItemsByProductId(Long productId) {
        return orderItemRepository.findByProductId(productId);
    }

    /**
     * 주문 항목 조회
     */
    @Transactional(readOnly = true)
    public OrderItem getOrderItem(Long id) {
        return orderItemRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("Order item not found: id=" + id));
    }

    /**
     * 주문 항목 삭제
     */
    @Transactional
    public void deleteOrderItem(Long id) {
        log.info("Deleting order item: id={}", id);
        orderItemRepository.deleteById(id);
        log.info("Order item deleted successfully: id={}", id);
    }

    /**
     * 주문별 항목 일괄 삭제
     */
    @Transactional
    public void deleteOrderItemsByOrderId(Long orderId) {
        log.info("Deleting order items by orderId: {}", orderId);
        orderItemRepository.deleteByOrderId(orderId);
        log.info("Order items deleted successfully for orderId: {}", orderId);
    }
}
