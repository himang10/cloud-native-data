package com.example.producer.service;

import com.example.producer.domain.User;
import com.example.producer.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * User 도메인 서비스
 * 
 * User 생성/수정/삭제 시 Outbox 이벤트를 함께 발행합니다.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class UserService {

    private final UserRepository userRepository;
    private final OutboxService outboxService;

    /**
     * 사용자 생성
     * 트랜잭션 내에서 User와 OutboxEvent를 함께 저장합니다.
     */
    @Transactional
    public User createUser(User user) {
        log.info("Creating user: email={}", user.getEmail());
        
        User savedUser = userRepository.save(user);
        
        // Outbox 이벤트 발행
        try {
            outboxService.publishEvent(
                    savedUser.getId(),
                    "user",
                    "created",
                    savedUser
            );
        } catch (Exception e) {
            log.error("Failed to publish outbox event, but user was created: id={}", savedUser.getId(), e);
            // OutboxEvent 실패해도 User는 저장됨 (트랜잭션 커밋)
        }
        
        log.info("User created successfully: id={}, email={}", savedUser.getId(), savedUser.getEmail());
        return savedUser;
    }

    /**
     * 사용자 수정
     */
    @Transactional
    public User updateUser(Long id, User user) {
        log.info("Updating user: id={}", id);
        
        User existingUser = userRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("User not found: id=" + id));
        
        existingUser.setName(user.getName());
        existingUser.setEmail(user.getEmail());
        
        User updatedUser = userRepository.save(existingUser);
        
        // Outbox 이벤트 발행
        outboxService.publishEvent(
                updatedUser.getId(),
                "user",
                "updated",
                updatedUser
        );
        
        log.info("User updated successfully: id={}", updatedUser.getId());
        return updatedUser;
    }

    /**
     * 사용자 삭제
     */
    @Transactional
    public void deleteUser(Long id) {
        log.info("Deleting user: id={}", id);
        
        User user = userRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("User not found: id=" + id));
        
        // Outbox 이벤트 발행 (삭제 전에 먼저 발행)
        outboxService.publishEvent(
                user.getId(),
                "user",
                "deleted",
                user
        );
        
        userRepository.delete(user);
        log.info("User deleted successfully: id={}", id);
    }

    /**
     * 사용자 조회
     */
    @Transactional(readOnly = true)
    public User getUser(Long id) {
        return userRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("User not found: id=" + id));
    }

    /**
     * 전체 사용자 조회
     */
    @Transactional(readOnly = true)
    public List<User> getAllUsers() {
        return userRepository.findAll();
    }
}

