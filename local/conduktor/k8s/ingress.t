apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
  name: ${TEAM_NAME}-${SERVICE_NAME}-ingress
spec:
  ingressClassName: nginx
  rules:
  - host: ${INGRESS_DOMAIN}
    http:
      paths:
      - backend:
          service:
            name: ${TEAM_NAME}-${SERVICE_NAME}
            port:
              number: 8080
        path: /
        pathType: Prefix
  tls:
  - hosts:
    - ${INGRESS_DOMAIN}
    secretName: ${TEAM_NAME}-${SERVICE_NAME}-tls-secret
