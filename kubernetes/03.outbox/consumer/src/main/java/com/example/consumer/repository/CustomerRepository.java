package com.example.consumer.repository;

import com.example.consumer.entity.Customer;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

/**
 * Customer Repository
 * 
 * Customer Entity의 CRUD 작업을 위한 Repository
 */
@Repository
public interface CustomerRepository extends JpaRepository<Customer, Long> {
    
    /**
     * customerId로 Customer 조회
     */
    Optional<Customer> findByCustomerId(Long customerId);
    
    /**
     * email로 Customer 조회
     */
    Optional<Customer> findByEmail(String email);
    
    /**
     * customerId로 Customer 삭제
     */
    void deleteByCustomerId(Long customerId);
}

