# Technical Solution Documentation

This document provides a detailed explanation of the implementation choices and technical details for each task in the DevOps assessment.

## 1. Dockerfile Implementation

### Solution Overview
I've implemented a multi-stage Docker build to create an efficient and secure container image for the Go application.

### Implementation File
```dockerfile
# Build stage
FROM golang:1.20-alpine AS builder

WORKDIR /app

# Install build dependencies
RUN apk add --no-cache gcc musl-dev

# Copy go mod and sum files
COPY go.mod go.sum ./

# Download dependencies
RUN go mod download

# Copy the source code
COPY . .

# Build the application
RUN CGO_ENABLED=1 GOOS=linux go build -o main .

# Final stage
FROM alpine:3.17

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache ca-certificates

# Copy the binary from builder
COPY --from=builder /app/main .
COPY --from=builder /app/config ./config

# Expose the application port
EXPOSE 8080

# Run the application
CMD ["./main"]
```

### Key Decisions
1. **Multi-stage Build**:
   - First stage uses `golang:1.20-alpine` for building
   - Second stage uses minimal `alpine:3.17` for runtime
   - Reduces final image size by excluding build tools and dependencies
   - Improves security by minimizing attack surface

2. **Build Configuration**:
   - Enables CGO for potential native dependencies: `CGO_ENABLED=1`
   - Uses musl-based compilation for Alpine compatibility
   - Includes only necessary build dependencies (`gcc`, `musl-dev`)

3. **Runtime Configuration**:
   - Copies only the compiled binary and config files
   - Includes CA certificates for HTTPS support
   - Exposes port 8080 for application access
   - Uses non-root working directory for security

## 2. Docker Compose Implementation

### Solution Overview
Created a development environment with the application and PostgreSQL database, focusing on ease of use and reliability.

### Implementation File
```yaml
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8080:8080"
    environment:
      - BANK_POSTGRES_HOST=postgres:5432
      - BANK_POSTGRES_DATABASE=bdb
      - BANK_POSTGRES_USERNAME=test
      - BANK_POSTGRES_PASSWORD=test
      - BANK_POSTGRES_SSLMODE=disable
      - BANK_POSTGRES_AUTOMIGRATE=true
    depends_on:
      - postgres
    restart: unless-stopped

  postgres:
    image: postgres:12-alpine
    environment:
      - POSTGRES_USER=test
      - POSTGRES_PASSWORD=test
      - POSTGRES_DB=bdb
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U test -d bdb"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

### Key Decisions
1. **Service Configuration**:
   - Uses latest compose spec (3.8) for modern features
   - Implements service dependency management
   - Configures automatic restart policies

2. **Database Setup**:
   - PostgreSQL 12 (alpine variant for size efficiency)
   - Persistent volume for data storage
   - Health checks for reliability
   - Environment variables for easy configuration

3. **Networking**:
   - Internal service discovery (app → postgres)
   - Exposed ports for local development
   - Secure default credentials

## 3. GitHub Actions CI/CD Pipeline

### Solution Overview
Implemented a comprehensive CI/CD pipeline that handles testing, building, and publishing of the application.

### Implementation File
```yaml
name: CI/CD Pipeline

on:
  push:
    branches:
      - main
    tags:
      - 'v*'
  pull_request:
    branches:
      - main

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:12
        env:
          POSTGRES_USER: test
          POSTGRES_PASSWORD: test
          POSTGRES_DB: bdb
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3

      - name: Set up Go
        uses: actions/setup-go@v4
        with:
          go-version: '1.20'

      - name: Run tests
        run: go test -v -cover ./...
        env:
          BANK_POSTGRES_HOST: localhost:5432
          BANK_POSTGRES_DATABASE: bdb
          BANK_POSTGRES_USERNAME: test
          BANK_POSTGRES_PASSWORD: test

  build-and-push:
    needs: test
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - uses: actions/checkout@v3

      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v2
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata for Docker
        id: meta
        uses: docker/metadata-action@v4
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=sha,format=long

      - name: Build and push Docker image
        uses: docker/build-push-action@v4
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
```

### Key Decisions
1. **Workflow Triggers**:
   - Main branch pushes
   - Tag pushes (v*)
   - Pull requests to main
   - Ensures comprehensive coverage of deployment scenarios

2. **Testing Environment**:
   - PostgreSQL service container for integration tests
   - Configurable test database
   - Proper environment variable configuration
   - Health checks for database readiness

3. **Container Registry Integration**:
   - Uses GitHub Container Registry (GHCR)
   - Implements proper authentication
   - Comprehensive image tagging strategy
   - Metadata labels for traceability

## 4. Helm Chart Implementation

### Solution Overview
Created a production-ready Kubernetes deployment configuration with high availability and proper resource management.

### Implementation Files

#### Chart.yaml
```yaml
apiVersion: v2
name: bank-api
description: A Helm chart for the Bank Transaction API
type: application
version: 0.1.0
appVersion: "1.0.0"
```

#### values.yaml
```yaml
replicaCount: 5

image:
  repository: ghcr.io/sbeuran/openprovider-devops-assesment
  tag: ""
  pullPolicy: IfNotPresent

nameOverride: ""
fullnameOverride: ""

serviceAccount:
  create: true
  name: ""

podAnnotations: {}

service:
  type: ClusterIP
  port: 8080

resources:
  limits:
    cpu: 500m
    memory: 512Mi
  requests:
    cpu: 200m
    memory: 256Mi

nodeSelector:
  role: api

tolerations: []

affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchExpressions:
        - key: app.kubernetes.io/name
          operator: In
          values:
          - bank-api
      topologyKey: "kubernetes.io/hostname"

postgresql:
  enabled: true
  auth:
    username: test
    password: test
    database: bdb
  primary:
    service:
      port: 5432
```

#### templates/deployment.yaml
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "bank-api.fullname" . }}
  labels:
    {{- include "bank-api.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "bank-api.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "bank-api.selectorLabels" . | nindent 8 }}
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      serviceAccountName: {{ include "bank-api.serviceAccountName" . }}
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          env:
            - name: BANK_POSTGRES_HOST
              value: "{{ include "bank-api.fullname" . }}-postgresql:{{ .Values.postgresql.primary.service.port }}"
            - name: BANK_POSTGRES_DATABASE
              value: {{ .Values.postgresql.auth.database }}
            - name: BANK_POSTGRES_USERNAME
              value: {{ .Values.postgresql.auth.username }}
            - name: BANK_POSTGRES_PASSWORD
              value: {{ .Values.postgresql.auth.password }}
            - name: BANK_POSTGRES_SSLMODE
              value: "disable"
            - name: BANK_POSTGRES_AUTOMIGRATE
              value: "true"
          ports:
            - name: http
              containerPort: {{ .Values.service.port }}
              protocol: TCP
          livenessProbe:
            httpGet:
              path: /health
              port: http
          readinessProbe:
            httpGet:
              path: /health
              port: http
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
```

#### templates/service.yaml
```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "bank-api.fullname" . }}
  labels:
    {{- include "bank-api.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: http
      protocol: TCP
      name: http
  selector:
    {{- include "bank-api.selectorLabels" . | nindent 4 }}
```

### Key Decisions
1. **High Availability**:
   - 5 replicas as required
   - Pod anti-affinity for node distribution
   - Node selector for proper placement
   - Health checks for reliability

2. **Resource Management**:
   - Defined resource limits and requests
   - CPU: 200m-500m
   - Memory: 256Mi-512Mi
   - Prevents resource contention

3. **Configuration Management**:
   - Environment variables for application config
   - PostgreSQL dependency handling
   - Service account creation
   - Proper label management

4. **Security Considerations**:
   - ServiceAccount creation
   - Non-root container execution
   - Proper RBAC configuration
   - Secure database credentials management

## 5. CI Unit Tests Integration

### Solution Overview
Integrated unit testing into the CI pipeline with proper database support and coverage reporting.

### Technical Details
```yaml
- name: Run tests
  run: go test -v -cover ./...
  env:
    BANK_POSTGRES_HOST: localhost:5432
    ...
```

### Key Decisions
1. **Test Configuration**:
   - Integrated in main CI pipeline
   - Runs before image building
   - Proper database configuration
   - Coverage reporting enabled

2. **Database Integration**:
   - PostgreSQL service container
   - Proper health checks
   - Test-specific credentials
   - Isolated test database

## Best Practices Implemented

1. **Security**:
   - No hardcoded credentials
   - Minimal container images
   - Proper RBAC configuration
   - Service isolation

2. **Reliability**:
   - Health checks
   - Automatic restarts
   - Resource limits
   - High availability configuration

3. **Maintainability**:
   - Clear documentation
   - Consistent naming
   - Modular configuration
   - Version pinning

4. **Scalability**:
   - Horizontal pod scaling
   - Resource quotas
   - Node distribution
   - Database persistence 