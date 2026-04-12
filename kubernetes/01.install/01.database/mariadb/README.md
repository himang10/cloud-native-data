# MariaDB 접속 정보

## 배포 현황
- **namespace**: kafka
- **이미지**: `docker.io/bitnamilegacy/mariadb:11.4.6-debian-12-r0`
- **Helm 차트**: `bitnami/mariadb 20.5.5` (App: MariaDB 11.4.6)
- **Pod**: `mariadb-1-0`
- **서비스**: `mariadb-1:3306`

## 내부 접속 (클러스터 내 Pod 간)
```
mariadb-1.kafka.svc.cluster.local:3306
mariadb-1.kafka:3306
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
```bash
# 클러스터 내부
mysql -h mariadb-1.kafka.svc.cluster.local -P 3306 -u skala -p cloud

# 포트포워딩
kubectl port-forward -n kafka svc/mariadb-1 3306:3306
mysql -h 127.0.0.1 -P 3306 -u root -p
```

## 설치 / 삭제
```bash
# 설치
bash install.sh

# 삭제
bash uninstall.sh
```

## CDC (Debezium) 설정
MariaDB는 Debezium Source Connector를 위해 binlog가 활성화되어 있습니다.
- `binlog_format: ROW`
- `binlog_row_image: FULL`
- `expire_logs_days: 10`

## 파일 구조
| 파일 | 설명 |
|------|------|
| `install.sh` | bitnami/mariadb Helm 설치 |
| `uninstall.sh` | Helm uninstall + PVC 삭제 |
| `upgrade.sh` | Helm upgrade |
| `custom-values.yaml` | MariaDB 설정값 (binlog CDC 설정 포함) |
