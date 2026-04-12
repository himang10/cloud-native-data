package com.example.consumer.repository;

import com.example.consumer.domain.ProductSummary;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface ProductSummaryRepository extends JpaRepository<ProductSummary, Long> {
    Optional<ProductSummary> findByEventId(String eventId);
}

