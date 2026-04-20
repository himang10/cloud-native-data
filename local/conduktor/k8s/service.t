apiVersion: v1
kind: Service
metadata:
  name: ${TEAM_NAME}-${SERVICE_NAME}
spec:
  selector:
    app: ${TEAM_NAME}-${SERVICE_NAME}
  ports:
    - name: http
      port: 8080
      targetPort: http
  type: ClusterIP