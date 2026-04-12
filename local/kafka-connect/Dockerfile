# Local Kafka Connect + Debezium image (multi-stage build)
# Base: apache/kafka:4.0.0
# Plugins:
#   - Debezium MySQL/MariaDB Source Connector (3.2.3.Final)
#   - Debezium PostgreSQL Source Connector (3.2.3.Final)
#   - Debezium JDBC Sink Connector (3.2.3.Final)
#   - JDBC drivers (PostgreSQL 42.7.1, MySQL 8.2.0, MariaDB 3.3.2)

# Stage 1: Download plugins using ubuntu:22.04 (has apt-get/curl)
FROM ubuntu:22.04 AS plugin-downloader

RUN apt-get update && apt-get install -y --no-install-recommends curl wget ca-certificates && \
    rm -rf /var/lib/apt/lists/*

ENV DEBEZIUM_VERSION=3.2.3.Final

# Debezium MySQL/MariaDB Source Connector
RUN mkdir -p /plugins/debezium-mysql && \
    cd /plugins/debezium-mysql && \
    curl -fsSL -O https://repo1.maven.org/maven2/io/debezium/debezium-connector-mysql/${DEBEZIUM_VERSION}/debezium-connector-mysql-${DEBEZIUM_VERSION}-plugin.tar.gz && \
    tar -xzf debezium-connector-mysql-${DEBEZIUM_VERSION}-plugin.tar.gz --strip-components=1 && \
    rm debezium-connector-mysql-${DEBEZIUM_VERSION}-plugin.tar.gz

# Debezium PostgreSQL Source Connector
RUN mkdir -p /plugins/debezium-postgres && \
    cd /plugins/debezium-postgres && \
    curl -fsSL -O https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/${DEBEZIUM_VERSION}/debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz && \
    tar -xzf debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz --strip-components=1 && \
    rm debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz

# Debezium JDBC Sink Connector + JDBC drivers
RUN mkdir -p /plugins/debezium-jdbc-sink && \
    cd /plugins/debezium-jdbc-sink && \
    curl -fsSL -O https://repo1.maven.org/maven2/io/debezium/debezium-connector-jdbc/${DEBEZIUM_VERSION}/debezium-connector-jdbc-${DEBEZIUM_VERSION}-plugin.tar.gz && \
    tar -xzf debezium-connector-jdbc-${DEBEZIUM_VERSION}-plugin.tar.gz --strip-components=1 && \
    rm debezium-connector-jdbc-${DEBEZIUM_VERSION}-plugin.tar.gz && \
    curl -fsSL -O https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.1/postgresql-42.7.1.jar && \
    curl -fsSL -O https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.2.0/mysql-connector-j-8.2.0.jar && \
    curl -fsSL -O https://repo1.maven.org/maven2/org/mariadb/jdbc/mariadb-java-client/3.3.2/mariadb-java-client-3.3.2.jar

# Stage 2: Final image
FROM apache/kafka:4.0.0

USER root

# Create /opt/kafka/logs and grant write permission to appuser
# (prevents Permission denied when log4j2 tries to create connect.log)
RUN mkdir -p /opt/kafka/logs /opt/kafka/plugins && \
    chown -R appuser:appuser /opt/kafka/logs /opt/kafka/plugins && \
    chmod -R 755 /opt/kafka/logs

# Replace connect-log4j2.yaml with console-only appender
# (prevents RollingFileAppender from writing to /opt/kafka/logs/connect.log)
RUN printf 'Configuration:\n  status: warn\n  Appenders:\n    Console:\n      name: STDOUT\n      target: SYSTEM_OUT\n      PatternLayout:\n        Pattern: "[%%d] %%p %%m (%%c)%%n"\n  Loggers:\n    Root:\n      level: INFO\n      AppenderRef:\n        ref: STDOUT\n' > /opt/kafka/config/connect-log4j2.yaml

# Copy plugins from Stage 1
COPY --from=plugin-downloader /plugins /opt/kafka/plugins
RUN chown -R appuser:appuser /opt/kafka/plugins

USER appuser

# connect-distributed.properties is mounted via docker-compose volume
CMD ["/opt/kafka/bin/connect-distributed.sh", "/opt/kafka/config/connect-distributed.properties"]
