# Kafka Pub/Sub 테스트

Docker 기반 Kafka 클라이언트를 사용한 Pub/Sub 테스트 스크립트

## 구성

```
pub-sub-test/
├── start-client.sh    # Kafka 클라이언트 컨테이너 시작
├── stop-client.sh     # Kafka 클라이언트 컨테이너 중지
├── create-topic.sh    # 토픽 생성
├── list-topics.sh     # 토픽 목록 확인
├── producer.sh        # 메시지 전송 (대화형)
├── consumer.sh        # 메시지 수신 (대화형)
├── test-all.sh        # 전체 자동 테스트
└── README.md          # 사용 가이드
```

## 사전 준비

1. Kafka가 실행 중이어야 합니다
2. `kafka-net` 네트워크가 존재해야 합니다
3. Kafka 브로커가 `kafka:9092`로 접근 가능해야 합니다

## 사용 방법

### 1. Kafka 클라이언트 시작

```bash
chmod +x *.sh
./start-client.sh
```

### 2. 자동 테스트 실행

```bash
./test-all.sh
```

이 스크립트는 다음을 자동으로 수행합니다:
- 토픽 생성 (test-topic)
- 토픽 목록 확인
- 5개의 테스트 메시지 전송
- 메시지 수신 및 출력

### 3. 수동 테스트

#### 토픽 생성
```bash
./create-topic.sh [토픽명] [파티션수] [복제계수]
# 예: ./create-topic.sh my-topic 3 1
```

#### 토픽 목록 확인
```bash
./list-topics.sh
```

#### Producer (메시지 전송)
```bash
./producer.sh [토픽명]
# 예: ./producer.sh test-topic
# 메시지 입력 후 Enter, 종료는 Ctrl+C
```

#### Consumer (메시지 수신)
```bash
./consumer.sh [토픽명]
# 예: ./consumer.sh test-topic
# 종료는 Ctrl+C
```

### 4. 클라이언트 중지

```bash
./stop-client.sh
```

## 테스트 시나리오

### 기본 Pub/Sub 테스트

```bash
# Terminal 1: Consumer 시작
./consumer.sh test-topic

# Terminal 2: Producer로 메시지 전송
./producer.sh test-topic
> Hello Kafka!
> This is a test message
> Goodbye!
```

### 여러 토픽 테스트

```bash
# 토픽 생성
./create-topic.sh topic-1 3 1
./create-topic.sh topic-2 3 1

# 각 토픽에 메시지 전송/수신
./producer.sh topic-1
./consumer.sh topic-1
```

## 문제 해결

### 클라이언트가 시작되지 않는 경우

```bash
# 네트워크 확인
docker network ls | grep kafka-net

# Kafka 상태 확인
docker ps | grep kafka
```

### 메시지가 수신되지 않는 경우

```bash
# 토픽 상세 정보 확인
docker exec -it kafka-client kafka-topics \
  --describe \
  --topic test-topic \
  --bootstrap-server kafka:9092

# 컨테이너 로그 확인
docker logs kafka-client
```

### 클라이언트 직접 접속

```bash
docker exec -it kafka-client bash

# 컨테이너 내부에서
kafka-topics --list --bootstrap-server kafka:9092
kafka-console-producer --topic test-topic --bootstrap-server kafka:9092
kafka-console-consumer --topic test-topic --from-beginning --bootstrap-server kafka:9092
```

## 참고사항

- 클라이언트 이미지: `confluentinc/cp-kafka:7.4.0`
- 네트워크: `kafka-net`
- Kafka 브로커: `kafka:9092`
- 기본 토픽: `test-topic` (파티션 3, 복제계수 1)
