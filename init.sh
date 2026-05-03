#!/bin/bash
set -e

echo "=== RAG Web UI Single Container Startup ==="

# Wait for MySQL to be ready
echo "Waiting for MySQL to start..."
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        echo "MySQL is ready!"
        break
    fi
    echo "Waiting for MySQL... ($i/30)"
    sleep 2
done

# Initialize MySQL database if not exists
echo "Initializing MySQL database..."
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS ragwebui CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS 'ragwebui'@'localhost' IDENTIFIED BY 'ragwebui';
GRANT ALL PRIVILEGES ON ragwebui.* TO 'ragwebui'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "MySQL database initialized."

# Wait for MinIO to be ready
echo "Waiting for MinIO to start..."
for i in {1..30}; do
    if curl -s http://localhost:9000/minio/health/live > /dev/null 2>&1; then
        echo "MinIO is ready!"
        break
    fi
    echo "Waiting for MinIO... ($i/30)"
    sleep 2
done

# Create MinIO bucket if not exists
echo "Creating MinIO bucket..."
export MC_HOST_minio=http://minioadmin:minioadmin@localhost:9000
mc alias set minio http://localhost:9000 minioadmin minioadmin 2>/dev/null || true
mc mb minio/documents 2>/dev/null || echo "Bucket 'documents' already exists or cannot create yet"

echo "=== All services initialized ==="
