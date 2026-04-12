#!/bin/bash

# Root 비밀번호 확인
echo "Root password: $(kubectl get secret mariadb-1 -o jsonpath='{.data.mariadb-root-password}' | base64 -d)"

# MariaDB 클라이언트 Pod로 접속
kubectl run my-mariadb-client --rm --tty -i --restart='Never' \
  --image docker.io/bitnami/mariadb:11.2.2-debian-11-r1 \
  --command -- mysql -h mariadb-1.mariadb.svc.cluster.local -uroot -p
