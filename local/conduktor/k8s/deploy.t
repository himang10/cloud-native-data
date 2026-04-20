apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${TEAM_NAME}-${SERVICE_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${TEAM_NAME}-${SERVICE_NAME}
  template:
    metadata:
      labels:
        app: ${TEAM_NAME}-${SERVICE_NAME}
    spec:
      containers:
        - name: conduktor-platform
          image: amdp-registry.skala-ai.com/library/conduktor-platform:latest
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: CDK_DATABASE_URL
              value: ${POSTGRES_URL}
            - name: CDK_LISTENING_PORT
              value: "8080"
            - name: CDK_ORGANIZATION_NAME
              value: MyOrganization
            - name: CDK_ADMIN_EMAIL
              value: admin@skala.com
            - name: CDK_ADMIN_PASSWORD
              value: admin
            - name: CDK_CLUSTERS_0_ID
              value: kubernetes-cluster
            - name: CDK_CLUSTERS_0_NAME
              value: kubernetes-cluster
            - name: CDK_CLUSTERS_0_BOOTSTRAPSERVERS
              value: my-kafka-cluster-kafka-bootstrap:9092
          readinessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 10
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 6
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: 30
            periodSeconds: 30
            timeoutSeconds: 5
            failureThreshold: 3
