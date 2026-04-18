#  CDC 관리 스크립트 모음

이 디렉토리에는 Kafka CDC(Change Data Capture) 운영 및 테스트를 위한 유틸리티 스크립트들이 포함되어 있습니다.

---

##  스크립트 목록

### 1 `list-kafka-topics.sh` - Kafka Topics 조회

Kafka 클러스터의 Topic 목록을 조회합니다.

**사용법:**
```bash
# 전체 Topics 조회
./list-kafka-topics.sh

# 특정 키워드로 필터링
./list-kafka-topics.sh mariadb
./list-kafka-topics.sh debezium
```

**출력 예시:**
```
 전체 Topics:
__debezium-heartbeat.mariadb
mariadb
mariadb-schema-changes
mariadb-cdc.cloud.users
mariadb.cloud.applicants
```

---

### 2 `insert-test-data.sh` - 테스트 데이터 관리

MariaDB에 테스트 데이터를 삽입/업데이트/삭제합니다.

**사용법:**
```bash
# INSERT: 1개 레코드 삽입
./insert-test-data.sh insert 1

# INSERT: 5개 레코드 삽입
./insert-test-data.sh insert 5

# UPDATE: 최근 3개 레코드 업데이트
./insert-test-data.sh update 3

# DELETE: 최근 2개 레코드 삭제
./insert-test-data.sh delete 2
```

**주요 기능:**
-  **INSERT**: 고유 ID와 타임스탬프로 새 사용자 생성
-  **UPDATE**: 최근 레코드의 이름 업데이트
-  **DELETE**: 최근 레코드 삭제
-  자동으로 전체 레코드 수 표시

---

### 3 `view-cdc-messages.sh` - CDC 메시지 조회

Kafka Topic의 CDC 메시지를 **jq로 포맷팅하여** 깔끔하게 표시합니다.

**사용법:**
```bash
# 기본: mariadb-cdc.cloud.users의 최근 10개 메시지
./view-cdc-messages.sh

# 특정 Topic의 5개 메시지 (처음부터)
./view-cdc-messages.sh mariadb-cdc.cloud.users 5 beginning

# 최신 3개 메시지만 보기
./view-cdc-messages.sh mariadb-cdc.cloud.users 3 latest

# 다른 테이블 조회
./view-cdc-messages.sh mariadb-cdc.cloud.applicants 10
```

**출력 예시:**
```json

 메시지 #1

{
  " ID": "test-user-1729590863-1",
  " Email": "test1729590863_1@example.com",
  " Name": "Test User 1729590863 #1",
  " Role": "INTERVIEWER",
  " Operation": " CREATE",
  " Deleted": "false",
  " Database": "cloud",
  " Table": "users",
  " Timestamp": "1729590863425",
  " Source Time": "1729590863000"
}
```

**주요 기능:**
-  jq를 사용한 컬러 포맷팅
-  작업 타입별 통계 (CREATE/UPDATE/DELETE 카운트)
-  이모지로 가독성 향상
-  작업 타입 아이콘 표시

---

### 4 `check-connector-status.sh` - Connector 상태 확인

Kafka Connector의 상태를 상세하게 확인합니다.

**사용법:**
```bash
# 기본 Connector (mariadb-source-connector) 확인
./check-connector-status.sh

# 특정 Connector 확인
./check-connector-status.sh my-connector-name
```

**출력 정보:**
-  등록된 Connector 목록
-  Connector 상세 상태 (RUNNING/FAILED/등)
-  Task 상태 및 Worker ID
-  관련 Kafka Topics
- / 동작 상태 검증

---

### 5 `check-binlog-status.sh` - Binlog 상태 확인

MariaDB의 Binlog 설정 및 CDC 준비 상태를 종합적으로 확인합니다.

**사용법:**
```bash
./check-binlog-status.sh
```

**확인 항목:**
-  Binlog 설정 (log_bin, binlog_format, binlog_row_image 등)
-  Binlog 파일 목록
-  Master 상태 및 현재 Binlog 위치
-  CDC 사용자(skala) 권한
-  데이터베이스 및 테이블 정보
-  CDC 준비 상태 요약

**출력 예시:**
```
 설정 검증

 Binlog 활성화: ON
 Binlog 형식: ROW (CDC 지원)

 권한 검증

 RELOAD 권한: 있음
 REPLICATION SLAVE 권한: 있음
 REPLICATION CLIENT 권한: 있음

 CDC를 위한 모든 설정이 완료되었습니다!
```

---

### 6 `cdc-test-flow.sh` - 전체 플로우 테스트

CDC의 전체 워크플로우를 단계별로 테스트합니다.

**사용법:**
```bash
./cdc-test-flow.sh
```

**테스트 시나리오:**
1.  Binlog 상태 확인
2.  Connector 상태 확인
3.  테스트 데이터 INSERT (2건)
4.  CDC 메시지 확인 (INSERT)
5.  데이터 UPDATE (2건)
6.  CDC 메시지 확인 (UPDATE)
7.  데이터 DELETE (2건)
8.  CDC 메시지 확인 (DELETE)

**특징:**
-  각 단계마다 대화형 확인 (Enter 키로 진행)
-  CDC 처리 대기 시간 자동 적용
-  최종 테스트 요약 제공

---

##  빠른 시작 가이드

### 1. 처음 시작할 때

```bash
# 1. Binlog 상태 확인
./check-binlog-status.sh

# 2. Connector 상태 확인
./check-connector-status.sh

# 3. Kafka Topics 확인
./list-kafka-topics.sh mariadb
```

### 2. CDC 테스트하기

```bash
# 간단한 테스트
./insert-test-data.sh insert 1
sleep 5
./view-cdc-messages.sh mariadb-cdc.cloud.users 1 latest

# 전체 플로우 테스트 (추천)
./cdc-test-flow.sh
```

### 3. 일상적인 모니터링

```bash
# Connector 상태 확인
./check-connector-status.sh

# 최근 CDC 메시지 확인
./view-cdc-messages.sh mariadb-cdc.cloud.users 10 latest

# Topic 목록 확인
./list-kafka-topics.sh mariadb
```

---

##  사용 시나리오

### 시나리오 1: 새 테이블 CDC 동작 확인

```bash
# 1. 테이블에 데이터 삽입
./insert-test-data.sh insert 3

# 2. Kafka Topics 확인 (새 Topic 생성 확인)
./list-kafka-topics.sh mariadb.cloud

# 3. CDC 메시지 확인
./view-cdc-messages.sh mariadb-cdc.cloud.users 3
```

### 시나리오 2: Connector 문제 진단

```bash
# 1. Connector 상태 확인
./check-connector-status.sh

# 2. Binlog 설정 확인
./check-binlog-status.sh

# 3. 로그 확인 (스크립트가 제공하는 명령어 사용)
kubectl logs -n kafka debezium-connect-cluster-connect-0 --tail=100
```

### 시나리오 3: 대량 데이터 테스트

```bash
# 1. 100개 레코드 삽입
./insert-test-data.sh insert 100

# 2. 메시지 확인 (최근 10개)
./view-cdc-messages.sh mariadb-cdc.cloud.users 10 latest

# 3. Topic 통계
./view-cdc-messages.sh mariadb-cdc.cloud.users 50 | grep "작업 타입 통계"
```

---

##  필수 요구사항

### 환경
-  Kubernetes 클러스터 접근 권한
-  `kubectl` CLI 설치
-  Kafka 및 MariaDB가 배포되어 있어야 함

### 선택사항 (권장)
-  **jq** - JSON 포맷팅용 (view-cdc-messages.sh에서 사용)
  ```bash
  # macOS
  brew install jq
  
  # Ubuntu/Debian
  sudo apt-get install jq
  
  # CentOS/RHEL
  sudo yum install jq
  ```

> **Note**: jq가 없어도 스크립트는 동작하지만, JSON이 포맷팅되지 않은 상태로 출력됩니다.

---

##  설정 커스터마이징

### Namespace 변경

각 스크립트 상단의 변수를 수정하세요:

```bash
# Kafka Namespace
NAMESPACE="kafka"

# MariaDB Namespace
NAMESPACE="mariadb"
```

### 데이터베이스 접속 정보 변경

`insert-test-data.sh`, `check-binlog-status.sh`:
```bash
DB_USER="root"
DB_PASSWORD="Skala25a\$23\$"
DATABASE="cloud"
```

---

##  문제 해결

### jq 관련 에러
```
 jq가 설치되어 있지 않습니다. 원본 JSON으로 표시합니다.
```
**해결**: jq를 설치하거나, JSON 원본 출력으로도 사용 가능합니다.

### Kafka Pod 연결 실패
```
Error from server: pods "my-kafka-cluster-kafka-pool-0" not found
```
**해결**: Pod 이름 확인 후 스크립트의 `KAFKA_POD` 변수 수정

### MariaDB 권한 에러
```
Access denied for user 'root'@'%'
```
**해결**: `DB_PASSWORD` 변수 확인 및 수정

---

##  관련 문서

- `../MARIADB_BINLOG_GUIDE.md` - MariaDB Binlog 설정 가이드
- `../CDC_DEPLOYMENT_SUCCESS.md` - CDC 배포 완료 보고서
- `../README.md` - 프로젝트 메인 문서

---

##  기여

스크립트 개선 아이디어나 버그 리포트는 언제든 환영합니다!

---

**작성일**: 2025년 10월 22일  
**버전**: 1.0  
**작성자**: Skala AI Team

