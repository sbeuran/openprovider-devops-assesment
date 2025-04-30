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