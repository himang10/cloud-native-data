# Kafka Connect Docker 실행 스크립트 (Debezium)

Strimzi KafkaConnect 리소스 설정을 Docker 컨테이너로 실행하는 스크립트 모음입니다.

---

## 목차
1. [run.sh - Kafka Connect 시작](#runsh)
2. [stop.sh - Kafka Connect 중지](#stopsh)
3. [logs.sh - 로그 확인](#logssh)
4. [clean.sh - 완전 삭제](#cleansh)
5. [사용 가이드](#사용-가이드)

---

## run.sh

Kafka Connect 컨테이너를 시작하는 메인 스크립트입니다.

```bash
#!/bin/bash

# Kafka Connect 설정
CONTAINER_NAME="kafka-connect-debezium"
IMAGE="amdp-registry.skala-ai.com/library/skala-kafka-connect:debezium-3.2.3-kafka-4.0"
KAFKA_BOOTSTRAP="my-kafka-cluster-kafka-bootstrap:9092"
REST_PORT="8083"

# 기존 컨테이너 확인 및 중지/삭제
if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
    echo "기존 컨테이너를 중지하고 삭제합니다..."
    docker stop ${CONTAINER_NAME}
    docker rm ${CONTAINER_NAME}
fi

echo "Kafka Connect 컨테이너를 시작합니다..."

# Docker 컨테이너 실행
docker run -d \
  --name ${CONTAINER_NAME} \
  -p ${REST_PORT}:8083 \
  -e CONNECT_BOOTSTRAP_SERVERS="${KAFKA_BOOTSTRAP}" \
  -e CONNECT_GROUP_ID="source-connect-cluster" \
  -e CONNECT_CONFIG_STORAGE_TOPIC="source-connect-configs" \
  -e CONNECT_CONFIG_STORAGE_REPLICATION_FACTOR=1 \
  -e CONNECT_OFFSET_STORAGE_TOPIC="source-connect-offsets" \
  -e CONNECT_OFFSET_STORAGE_REPLICATION_FACTOR=1 \
  -e CONNECT_STATUS_STORAGE_TOPIC="source-connect-status" \
  -e CONNECT_STATUS_STORAGE_REPLICATION_FACTOR=1 \
  -e CONNECT_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e CONNECT_KEY_CONVERTER_SCHEMAS_ENABLE=true \
  -e CONNECT_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e CONNECT_VALUE_CONVERTER_SCHEMAS_ENABLE=true \
  -e CONNECT_INTERNAL_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e CONNECT_INTERNAL_KEY_CONVERTER_SCHEMAS_ENABLE=false \
  -e CONNECT_INTERNAL_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e CONNECT_INTERNAL_VALUE_CONVERTER_SCHEMAS_ENABLE=false \
  -e CONNECT_REST_ADVERTISED_HOST_NAME="localhost" \
  -e CONNECT_REST_PORT=8083 \
  -e CONNECT_PLUGIN_PATH="/usr/share/java,/usr/share/confluent-hub-components" \
  -e KAFKA_HEAP_OPTS="-Xms1g -Xmx1g" \
  --memory="2g" \
  --cpus="1.0" \
  ${IMAGE}

# 컨테이너 시작 대기
echo "Kafka Connect가 시작될 때까지 대기 중..."
sleep 15

# 상태 확인
if docker ps | grep -q ${CONTAINER_NAME}; then
    echo ""
    echo "===================================="
    echo "Kafka Connect가 성공적으로 시작되었습니다!"
    echo "===================================="
    echo ""
    echo "접속 정보:"
    echo "  REST API: http://localhost:${REST_PORT}"
    echo "  Kafka Bootstrap: ${KAFKA_BOOTSTRAP}"
    echo "  Group ID: source-connect-cluster"
    echo ""
    echo "상태 확인:"
    echo "  curl http://localhost:${REST_PORT}/ | jq"
    echo ""
    echo "커넥터 목록:"
    echo "  curl http://localhost:${REST_PORT}/connectors | jq"
    echo ""
    echo "플러그인 목록:"
    echo "  curl http://localhost:${REST_PORT}/connector-plugins | jq"
    echo ""
    echo "컨테이너 로그:"
    echo "  docker logs -f ${CONTAINER_NAME}"
    echo ""
    echo "컨테이너 중지:"
    echo "  docker stop ${CONTAINER_NAME}"
    echo ""
else
    echo ""
    echo "오류: Kafka Connect 시작에 실패했습니다."
    echo "로그 확인: docker logs ${CONTAINER_NAME}"
    exit 1
fi
```

---

## stop.sh

Kafka Connect 컨테이너를 중지하는 스크립트입니다.

```bash
#!/bin/bash

CONTAINER_NAME="kafka-connect-debezium"

if [ "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    echo "Kafka Connect 컨테이너를 중지합니다..."
    docker stop ${CONTAINER_NAME}
    echo "컨테이너가 중지되었습니다."
else
    echo "실행 중인 Kafka Connect 컨테이너가 없습니다."
fi
```

---

## logs.sh

Kafka Connect 컨테이너의 로그를 확인하는 스크립트입니다.

```bash
#!/bin/bash

CONTAINER_NAME="kafka-connect-debezium"

if [ "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
    echo "Kafka Connect 로그를 확인합니다 (Ctrl+C로 종료)..."
    echo ""
    docker logs -f ${CONTAINER_NAME}
else
    echo "실행 중인 Kafka Connect 컨테이너가 없습니다."
    echo ""
    echo "마지막 로그 확인:"
    docker logs ${CONTAINER_NAME} 2>/dev/null || echo "로그가 없습니다."
fi
```

---

## clean.sh

Kafka Connect 컨테이너를 완전히 삭제하는 스크립트입니다.

```bash
#!/bin/bash

CONTAINER_NAME="kafka-connect-debezium"

echo "경고: 이 스크립트는 Kafka Connect 컨테이너를 삭제합니다."
read -p "계속하시겠습니까? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # 컨테이너 중지 및 삭제
    if [ "$(docker ps -aq -f name=${CONTAINER_NAME})" ]; then
        echo "컨테이너를 중지하고 삭제합니다..."
        docker stop ${CONTAINER_NAME} 2>/dev/null
        docker rm ${CONTAINER_NAME}
        echo "컨테이너가 삭제되었습니다."
    fi
    
    echo ""
    echo "Kafka Connect 컨테이너가 삭제되었습니다."
    echo "참고: Kafka 토픽의 데이터는 Kafka 클러스터에 남아있습니다."
else
    echo "취소되었습니다."
fi
```

---

## 사용 가이드

### 빠른 시작

```bash
# 1. 각 스크립트를 파일로 저장
# 2. 실행 권한 부여
chmod +x run.sh stop.sh logs.sh clean.sh

# 3. Kafka Connect 시작
./run.sh

# 4. 상태 확인
curl http://localhost:8083/ | jq
```

### 접속 정보

| 항목 | 값 |
|------|-----|
| REST API | http://localhost:8083 |
| Kafka Bootstrap | my-kafka-cluster-kafka-bootstrap:9092 |
| Group ID | source-connect-cluster |
| JVM Heap | -Xms1g -Xmx1g |
| Memory Limit | 2GB |
| CPU Limit | 1.0 코어 |

### Kafka Connect 설정

**내부 토픽:**
- Config: `source-connect-configs` (복제 팩터: 1)
- Offset: `source-connect-offsets` (복제 팩터: 1)
- Status: `source-connect-status` (복제 팩터: 1)

**컨버터 설정:**
- Key/Value Converter: `JsonConverter` (스키마 활성화)
- Internal Key/Value Converter: `JsonConverter` (스키마 비활성화)

### REST API 사용 예제

**1. 상태 확인**
```bash
curl http://localhost:8083/ | jq
```

**2. 설치된 플러그인 확인**
```bash
curl http://localhost:8083/connector-plugins | jq
```

**3. 커넥터 목록 조회**
```bash
curl http://localhost:8083/connectors | jq
```

**4. Debezium MariaDB 커넥터 생성**
```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d '{
    "name": "mariadb-connector",
    "config": {
      "connector.class": "io.debezium.connector.mysql.MySqlConnector",
      "database.hostname": "localhost",
      "database.port": "3306",
      "database.user": "skala",
      "database.password": "Skala25a!23$",
      "database.server.id": "1",
      "database.server.name": "mariadb",
      "database.include.list": "cloud",
      "topic.prefix": "dbz-mariadb",
      "schema.history.internal.kafka.bootstrap.servers": "my-kafka-cluster-kafka-bootstrap:9092",
      "schema.history.internal.kafka.topic": "schema-changes.mariadb"
    }
  }'
```

**5. 커넥터 상태 확인**
```bash
curl http://localhost:8083/connectors/mariadb-connector/status | jq
```

**6. 커넥터 삭제**
```bash
curl -X DELETE http://localhost:8083/connectors/mariadb-connector
```

### 로그 확인

```bash
# 실시간 로그
./logs.sh

# 또는
docker logs -f kafka-connect-debezium
```

### 문제 해결

**포트 충돌**
```bash
# 8083 포트 사용 확인
lsof -i :8083
netstat -tulpn | grep 8083
```

**Kafka 연결 실패**
```bash
# Kafka 브로커 접근 확인
docker exec -it kafka-connect-debezium \
  kafka-broker-api-versions --bootstrap-server my-kafka-cluster-kafka-bootstrap:9092
```

**커넥터 생성 실패**
```bash
# 로그에서 에러 확인
docker logs kafka-connect-debezium | grep ERROR

# 플러그인 확인
curl http://localhost:8083/connector-plugins | jq
```

**네트워크 연결 문제**
```bash
# Kafka와 같은 네트워크에 연결
docker network ls
docker network connect <kafka-network> kafka-connect-debezium
```

### Strimzi와의 차이점

| 항목 | Strimzi | Docker |
|------|---------|--------|
| 커넥터 관리 | KafkaConnector CRD | REST API |
| 설정 관리 | ConfigMap | 환경 변수 |
| 자동 재시작 | Kubernetes | 수동 |
| 스케일링 | replicas | 수동 |
| 로깅 | kubectl logs | docker logs |

### 네트워크 설정

**로컬 환경에서 사용 시:**
```bash
# Kafka와 MariaDB가 Docker 네트워크에 있어야 함
docker network create kafka-net

# run.sh에 네트워크 추가
docker run -d \
  --network kafka-net \
  ...
```

**Kubernetes 클러스터의 Kafka에 연결 시:**
- Kafka 서비스를 NodePort나 LoadBalancer로 노출
- 또는 `KAFKA_BOOTSTRAP` 변수를 외부 IP로 변경

### 커스터마이징

**Kafka 브로커 변경:**
```bash
# run.sh에서 수정
KAFKA_BOOTSTRAP="your-kafka-broker:9092"
```

**플러그인 경로 추가:**
```bash
# run.sh에서 수정
-e CONNECT_PLUGIN_PATH="/usr/share/java,/usr/share/confluent-hub-components,/custom/plugins" \
-v /local/plugins:/custom/plugins:ro \
```

**리소스 제한 조정:**
```bash
# run.sh에서 수정
-e KAFKA_HEAP_OPTS="-Xms2g -Xmx2g" \
--memory="4g" \
--cpus="2.0" \
```

### 참고사항

- Strimzi의 `strimzi.io/use-connector-resources: "true"` 어노테이션은 Docker 환경에서는 적용되지 않습니다
- 커넥터는 REST API로 직접 관리해야 합니다
- 내부 토픽(configs, offsets, status)은 Kafka 클러스터에 자동으로 생성됩니다
- 컨테이너를 삭제해도 Kafka의 토픽과 데이터는 유지됩니다
- 프로덕션 환경에서는 복제 팩터를 3으로 설정하는 것을 권장합니다

### MariaDB와 통합 사용

```bash
# 1. MariaDB 시작
cd mariadb
./run.sh

# 2. Kafka Connect 시작
cd kafka-connect
./run.sh

# 3. Debezium 커넥터 생성 (위의 REST API 예제 참고)

# 4. 토픽 확인
kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic dbz-mariadb.cloud.your_table \
  --from-beginning
```
