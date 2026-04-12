package com.example.consumer.repository;

import com.example.consumer.domain.OrderSummary;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface OrderSummaryRepository extends JpaRepository<OrderSummary, Long> {
    Optional<OrderSummary> findByEventId(String eventId);
    List<OrderSummary> findByUserId(Long userId);
}

