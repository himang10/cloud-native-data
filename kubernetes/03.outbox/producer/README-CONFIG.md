# 설정 파일 구조

이 프로젝트는 프로파일별로 설정 파일을 분리하여 관리합니다.

## 설정 파일 구조

```
src/main/resources/
├── application.yml           # 공통 설정 (환경 변수 사용)
├── application-local.yml     # 로컬 개발 환경 설정
└── application-prod.yml      # 프로덕션 환경 설정
```

## 파일별 역할

### application.yml
- 모든 환경에서 공통으로 사용되는 설정
- 환경 변수를 사용하여 민감한 정보 관리
- 기본값 제공

### application-local.yml
- 로컬 개발 환경용 설정
- 상세한 로그 출력 (DEBUG)
- SQL 로그 출력
- 개발 편의성을 위한 설정

### application-prod.yml
- 프로덕션 환경용 설정
- 최적화된 로그 레벨 (INFO)
- SQL 로그 비활성화
- 보안 강화 설정

## 환경 변수 사용

### 필수 환경 변수
```bash
DB_PASSWORD          # 데이터베이스 비밀번호
```

### 선택적 환경 변수 (기본값 제공)
```bash
SPRING_PROFILES_ACTIVE      # 활성 프로파일 (기본값: local)
DB_URL                      # DB 연결 URL
DB_USERNAME                 # DB 사용자명
HIKARI_MAX_POOL_SIZE        # 커넥션 풀 최대 크기
SERVER_PORT                 # 서버 포트
LOG_LEVEL_ROOT              # 루트 로그 레벨
LOG_LEVEL_APP               # 애플리케이션 로그 레벨
```

## 실행 방법

### 로컬 실행
```bash
java -jar -Dspring.profiles.active=local \
       -DDB_PASSWORD=your_password \
       app.jar
```

### 프로덕션 실행
```bash
java -jar -Dspring.profiles.active=prod \
       -DDB_PASSWORD=your_password \
       app.jar
```

### 환경 변수 파일 사용
```bash
# .env 파일 생성
cp .env.example .env
# .env 파일 수정

# 환경 변수 로드 후 실행
export $(cat .env | xargs)
java -jar app.jar
```

## Docker 실행

### docker-compose.yml 예제
```yaml
version: '3.8'
services:
  outbox-producer:
    image: outbox-producer:latest
    environment:
      SPRING_PROFILES_ACTIVE: prod
      DB_URL: jdbc:mariadb://db:3306/cloud
      DB_USERNAME: ${DB_USERNAME}
      DB_PASSWORD: ${DB_PASSWORD}
    ports:
      - "8080:8080"
```

## Kubernetes 배포

### ConfigMap 예제
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: outbox-producer-config
data:
  SPRING_PROFILES_ACTIVE: "prod"
  HIKARI_MAX_POOL_SIZE: "20"
```

### Secret 예제
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: outbox-producer-secret
type: Opaque
stringData:
  DB_PASSWORD: your_secure_password
```

### Deployment 예제
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: outbox-producer
spec:
  template:
    spec:
      containers:
      - name: outbox-producer
        image: outbox-producer:latest
        env:
        - name: SPRING_PROFILES_ACTIVE
          valueFrom:
            configMapKeyRef:
              name: outbox-producer-config
              key: SPRING_PROFILES_ACTIVE
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: outbox-producer-secret
              key: DB_PASSWORD
```

## 주의사항

1. **보안**
   - 민감한 정보는 환경 변수로 관리
   - `.env` 파일은 `.gitignore`에 추가
   - 프로덕션에서는 `HEALTH_SHOW_DETAILS: never` 설정

2. **로깅**
   - 로컬: DEBUG 레벨로 상세 정보 출력
   - 프로덕션: INFO 레벨로 필요한 정보만 출력
   - SQL 로그는 프로덕션에서 비활성화

3. **성능**
   - 프로덕션에서는 커넥션 풀 크기 조정
   - 적절한 타임아웃 설정
   - JVM 옵션 최적화 고려

## 문제 해결

### 데이터베이스 연결 실패
- 환경 변수 `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` 확인
- 방화벽 및 네트워크 설정 확인

### 포트 충돌
- `SERVER_PORT` 환경 변수로 변경
- 또는 `server.port` 속성 수정

### 로그가 출력되지 않음
- `LOG_LEVEL_ROOT`, `LOG_LEVEL_APP` 환경 변수 확인
- 프로파일이 올바르게 활성화되었는지 확인
