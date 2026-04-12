package com.example.consumer.controller;

import com.example.consumer.domain.OrderSummary;
import com.example.consumer.domain.ProductSummary;
import com.example.consumer.domain.UserSummary;
import com.example.consumer.service.OrderSummaryService;
import com.example.consumer.service.ProductSummaryService;
import com.example.consumer.service.UserSummaryService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * Summary 조회 REST API Controller
 * 
 * PostgreSQL에 저장된 Summary 데이터를 조회합니다.
 */
@RestController
@RequestMapping("/api/summary")
@RequiredArgsConstructor
public class SummaryController {

    private final UserSummaryService userSummaryService;
    private final ProductSummaryService productSummaryService;
    private final OrderSummaryService orderSummaryService;

    // ========== User Summary ==========
    
    @GetMapping("/users/{userId}")
    public ResponseEntity<UserSummary> getUserSummary(@PathVariable Long userId) {
        UserSummary summary = userSummaryService.getUserSummary(userId);
        return ResponseEntity.ok(summary);
    }

    @GetMapping("/users")
    public ResponseEntity<List<UserSummary>> getAllUserSummaries() {
        List<UserSummary> summaries = userSummaryService.getAllUserSummaries();
        return ResponseEntity.ok(summaries);
    }

    // ========== Product Summary ==========
    
    @GetMapping("/products/{productId}")
    public ResponseEntity<ProductSummary> getProductSummary(@PathVariable Long productId) {
        ProductSummary summary = productSummaryService.getProductSummary(productId);
        return ResponseEntity.ok(summary);
    }

    @GetMapping("/products")
    public ResponseEntity<List<ProductSummary>> getAllProductSummaries() {
        List<ProductSummary> summaries = productSummaryService.getAllProductSummaries();
        return ResponseEntity.ok(summaries);
    }

    // ========== Order Summary ==========
    
    @GetMapping("/orders/{orderId}")
    public ResponseEntity<OrderSummary> getOrderSummary(@PathVariable Long orderId) {
        OrderSummary summary = orderSummaryService.getOrderSummary(orderId);
        return ResponseEntity.ok(summary);
    }

    @GetMapping("/orders/user/{userId}")
    public ResponseEntity<List<OrderSummary>> getOrderSummariesByUserId(@PathVariable Long userId) {
        List<OrderSummary> summaries = orderSummaryService.getOrderSummariesByUserId(userId);
        return ResponseEntity.ok(summaries);
    }

    @GetMapping("/orders")
    public ResponseEntity<List<OrderSummary>> getAllOrderSummaries() {
        List<OrderSummary> summaries = orderSummaryService.getAllOrderSummaries();
        return ResponseEntity.ok(summaries);
    }
}

