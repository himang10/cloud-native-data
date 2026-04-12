package com.example.consumer;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.kafka.annotation.EnableKafka;

/**
 * Outbox Pattern Consumer Application
 * 
 * Kafka로부터 Outbox 이벤트를 수신하여 PostgreSQL에 저장합니다.
 */
@SpringBootApplication
@EnableKafka
public class ConsumerApplication {

    public static void main(String[] args) {
        SpringApplication.run(ConsumerApplication.class, args);
    }
}

