# Redis (Valkey) 접속 정보

## 배포 현황
- **namespace**: kafka
- **이미지**: `registry-1.docker.io/bitnami/valkey:latest` (Valkey = Redis 완전 호환 오픈소스)
- **Helm 차트**: `bitnami/valkey 5.4.9` (App: Valkey 9.0.3)
- **Pod**: `redis-1-primary-0`
- **서비스**: `redis-1-primary:6379`

> **참고**: Valkey는 2024년 Redis SSPL 라이선스 변경 이후 Linux Foundation 주도로 만들어진  
> Redis 완전 호환 BSD 오픈소스 포크입니다. Redis API/CLI/프로토콜이 동일합니다.

## 내부 접속 (클러스터 내 Pod 간)
```
redis-1-primary.kafka.svc.cluster.local:6379
redis-1-primary.kafka:6379
```

## 계정 정보

### default (관리자)
- Password: `Skala25a!23$`

### ACL 사용자
| 사용자 | 비밀번호 | 권한 |
|--------|----------|------|
| `admin` | `Skala25a!23$` | 전체 권한 |
| `skala` | `Skala25a!23$` | read/write (FLUSH/SHUTDOWN 제외) |

## 접속 예시
```bash
# 클러스터 내부 (redis-cli)
REDISCLI_AUTH="Skala25a!23$" redis-cli -h redis-1-primary.kafka.svc.cluster.local -p 6379

# 또는 valkey-cli
REDISCLI_AUTH="Skala25a!23$" valkey-cli -h redis-1-primary.kafka

# 포트포워딩
kubectl port-forward -n kafka svc/redis-1-primary 6379:6379
```

## 설치 / 삭제
```bash
# 설치 (bitnami/valkey 차트 사용)
bash install.sh

# 삭제
bash uninstall.sh
```

## 파일 구조
| 파일 | 설명 |
|------|------|
| `install.sh` | bitnami/valkey Helm 설치 |
| `uninstall.sh` | Helm uninstall + PVC 삭제 |
| `upgrade.sh` | Helm upgrade |
| `custom-values.yaml` | Valkey 설정값 (standalone, auth, persistence 등) |

> **변경 이력**: bitnami/redis 이미지 무료 제공 종료(2025.08) → bitnami/valkey 차트로 전환
