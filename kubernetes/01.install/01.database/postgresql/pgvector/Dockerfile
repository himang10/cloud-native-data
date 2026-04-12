FROM pgvector/pgvector:pg15 AS builder

#FROM bitnamilegacy/postgresql:16.3.0-debian-12-r19
FROM bitnamilegacy/postgresql:15.2.0-debian-11-r31

COPY --from=builder /usr/lib/postgresql/15/lib/vector.so /opt/bitnami/postgresql/lib/
COPY --from=builder /usr/share/postgresql/15/extension/vector* /opt/bitnami/postgresql/share/extension/

