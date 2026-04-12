# MongoDB 접속 정보

## 배포 현황
- **namespace**: kafka
- **이미지**: `docker.io/mongo:8.0` (공식 이미지)
- **설치 방식**: `kubectl apply -f mongodb-manifests.yaml`
- **Pod**: `mongodb-1-0`
- **서비스**: `mongodb-1:27017`

## 내부 접속 (클러스터 내 Pod 간)
```
mongodb-1.kafka.svc.cluster.local:27017
mongodb-1.kafka:27017
```

## 계정 정보

### admin
- UserName: `root`
- Password: `Skala25a!23$`

### 일반 사용자
- Database: `cloud`
- UserName: `skala`
- Password: `Skala25a!23$`

## 접속 예시
```
# 클러스터 내부
mongodb://root:Skala25a!23$@mongodb-1.kafka.svc.cluster.local:27017/?authSource=admin

# 일반 사용자
mongodb://skala:Skala25a!23$@mongodb-1.kafka.svc.cluster.local:27017/cloud
```

## 설치 / 삭제
```bash
# 설치
bash install.sh

# 삭제 (PVC 포함)
bash uninstall.sh

# 업그레이드 (mongodb-manifests.yaml 수정 후)
bash upgrade.sh
```

## 파일 구조
| 파일 | 설명 |
|------|------|
| `mongodb-manifests.yaml` | Secret, ConfigMap, StatefulSet, Service 정의 |
| `install.sh` | `kubectl apply` 설치 스크립트 |
| `uninstall.sh` | `kubectl delete` 삭제 스크립트 |
| `upgrade.sh` | `kubectl apply` 업그레이드 스크립트 |

> **참고**: bitnami/mongodb 이미지는 2025년 8월부터 무료 제공 종료. 공식 `docker.io/mongo:8.0` 이미지로 대체함.

