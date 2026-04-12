package com.example.consumer.repository;

import com.example.consumer.domain.UserSummary;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface UserSummaryRepository extends JpaRepository<UserSummary, Long> {
    Optional<UserSummary> findByEventId(String eventId);
}

