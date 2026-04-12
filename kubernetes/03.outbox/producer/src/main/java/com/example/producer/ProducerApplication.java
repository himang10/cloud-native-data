package com.example.producer;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.transaction.annotation.EnableTransactionManagement;

/**
 * Outbox Pattern Producer Application
 * 
 * MariaDB에 도메인 데이터와 Outbox 이벤트를 트랜잭션 내에서 함께 저장합니다.
 * Debezium이 outbox_events 테이블을 CDC하여 Kafka로 이벤트를 전송합니다.
 */
@SpringBootApplication
@EnableTransactionManagement
public class ProducerApplication {

    public static void main(String[] args) {
        SpringApplication.run(ProducerApplication.class, args);
    }
}

