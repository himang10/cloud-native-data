FROM quay.io/strimzi/kafka:0.48.0-kafka-4.0.0
USER root:root

# Kafka 4.0.0 호환 버전으로 업데이트
ENV DEBEZIUM_VERSION=3.2.3.Final
ENV JDBC_VERSION=10.8.0
ENV ELASTICSEARCH_VERSION=14.1.0

# ==========================================
# SOURCE CONNECTORS (DB → Kafka)
# ==========================================

# Debezium MySQL/MariaDB Source Connector
RUN mkdir -p /opt/kafka/plugins/debezium-mysql && \
    cd /opt/kafka/plugins/debezium-mysql && \
    curl -L -O https://repo1.maven.org/maven2/io/debezium/debezium-connector-mysql/${DEBEZIUM_VERSION}/debezium-connector-mysql-${DEBEZIUM_VERSION}-plugin.tar.gz && \
    tar -xzf debezium-connector-mysql-${DEBEZIUM_VERSION}-plugin.tar.gz --strip-components=1 && \
    rm debezium-connector-mysql-${DEBEZIUM_VERSION}-plugin.tar.gz

# Debezium PostgreSQL Source Connector
RUN mkdir -p /opt/kafka/plugins/debezium-postgres && \
    cd /opt/kafka/plugins/debezium-postgres && \
    curl -L -O https://repo1.maven.org/maven2/io/debezium/debezium-connector-postgres/${DEBEZIUM_VERSION}/debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz && \
    tar -xzf debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz --strip-components=1 && \
    rm debezium-connector-postgres-${DEBEZIUM_VERSION}-plugin.tar.gz

# Debezium MongoDB Source Connector (선택사항)
RUN mkdir -p /opt/kafka/plugins/debezium-mongodb && \
    cd /opt/kafka/plugins/debezium-mongodb && \
    curl -L -O https://repo1.maven.org/maven2/io/debezium/debezium-connector-mongodb/${DEBEZIUM_VERSION}/debezium-connector-mongodb-${DEBEZIUM_VERSION}-plugin.tar.gz && \
    tar -xzf debezium-connector-mongodb-${DEBEZIUM_VERSION}-plugin.tar.gz --strip-components=1 && \
    rm debezium-connector-mongodb-${DEBEZIUM_VERSION}-plugin.tar.gz

# ==========================================
# SINK CONNECTORS (Kafka → Target)
# ==========================================

# Confluent JDBC Sink Connector (Kafka → DB)
RUN mkdir -p /opt/kafka/plugins/kafka-connect-jdbc && \
    cd /opt/kafka/plugins/kafka-connect-jdbc && \
    curl -L -O https://packages.confluent.io/maven/io/confluent/kafka-connect-jdbc/${JDBC_VERSION}/kafka-connect-jdbc-${JDBC_VERSION}.jar && \
    curl -L -O https://repo1.maven.org/maven2/org/slf4j/slf4j-api/1.7.36/slf4j-api-1.7.36.jar && \
    # JDBC 드라이버들
    curl -L -O https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.2.0/mysql-connector-j-8.2.0.jar && \
    curl -L -O https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.1/postgresql-42.7.1.jar && \
    curl -L -O https://repo1.maven.org/maven2/org/mariadb/jdbc/mariadb-java-client/3.3.2/mariadb-java-client-3.3.2.jar

# Debezium JDBC Sink Connector (Kafka → DB, Debezium 버전)
RUN mkdir -p /opt/kafka/plugins/debezium-jdbc-sink && \
    cd /opt/kafka/plugins/debezium-jdbc-sink && \
    curl -L -O https://repo1.maven.org/maven2/io/debezium/debezium-connector-jdbc/${DEBEZIUM_VERSION}/debezium-connector-jdbc-${DEBEZIUM_VERSION}-plugin.tar.gz && \
    tar -xzf debezium-connector-jdbc-${DEBEZIUM_VERSION}-plugin.tar.gz --strip-components=1 && \
    rm debezium-connector-jdbc-${DEBEZIUM_VERSION}-plugin.tar.gz && \
    # JDBC 드라이버 추가
    curl -L -O https://repo1.maven.org/maven2/com/mysql/mysql-connector-j/8.2.0/mysql-connector-j-8.2.0.jar && \
    curl -L -O https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.1/postgresql-42.7.1.jar

USER 1001
