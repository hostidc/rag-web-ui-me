# Multi-stage build for RAG Web UI - Single Container Architecture
FROM ubuntu:22.04 AS base

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai \
    PYTHONUNBUFFERED=1 \
    NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    gnupg \
    lsb-release \
    software-properties-common \
    build-essential \
    supervisor \
    nginx \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# Install MySQL
RUN apt-get update && apt-get install -y \
    mysql-server \
    && rm -rf /var/lib/apt/lists/*

# Install Python 3.11 (Ubuntu 22.04 official repository includes python3.11)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-venv \
    python3.11-dev \
    default-libmysqlclient-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3.11 /usr/bin/python \
    && ln -sf /usr/bin/python3.11 /usr/bin/python3

# Install pip
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11

# Install Node.js 20 and pnpm
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get update && apt-get install -y nodejs && \
    npm install -g pnpm@8 && \
    rm -rf /var/lib/apt/lists/*

# Install MinIO
RUN curl -LO https://dl.min.io/server/minio/release/linux-amd64/minio && \
    chmod +x minio && \
    mv minio /usr/local/bin/

# Install MinIO Client (mc)
RUN curl -LO https://dl.min.io/client/mc/release/linux-amd64/mc && \
    chmod +x mc && \
    mv mc /usr/local/bin/

# Create directories
RUN mkdir -p /app/backend /app/frontend /data/mysql /data/chroma /data/minio /var/log/supervisor /app/uploads

# ==================== Backend Stage ====================
FROM base AS backend-builder

WORKDIR /app/backend

# Copy backend requirements and install Python packages
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy backend code
COPY backend/ .

# ==================== Frontend Stage ====================
FROM base AS frontend-builder

WORKDIR /app/frontend

# Copy frontend files
COPY frontend/package.json frontend/pnpm-lock.yaml ./
RUN pnpm install --no-frozen-lockfile

COPY frontend/ .

# Build with verbose output
RUN echo "Starting Next.js build..." && \
    pnpm build 2>&1 | tee /tmp/build.log && \
    echo "Build completed successfully" || \
    (echo "Build failed! Last 50 lines of log:" && tail -n 50 /tmp/build.log && exit 1)

# ==================== Final Stage ====================
FROM base

WORKDIR /app

# Copy backend from builder
COPY --from=backend-builder /app/backend /app/backend
COPY --from=backend-builder /usr/local/lib/python3.11/dist-packages /usr/local/lib/python3.11/dist-packages

# Copy frontend from builder
COPY --from=frontend-builder /app/frontend/.next/standalone /app/frontend
COPY --from=frontend-builder /app/frontend/.next/static /app/frontend/.next/static
COPY --from=frontend-builder /app/frontend/public /app/frontend/public

# Copy nginx configuration for single container
COPY nginx.single.conf /etc/nginx/nginx.conf

# Copy and setup initialization script
COPY init.sh /app/init.sh
RUN chmod +x /app/init.sh

# Create supervisor configuration
COPY <<'EOF' /etc/supervisor/conf.d/supervisord.conf
[supervisord]
nodaemon=true
logfile=/var/log/supervisor/supervisord.log
pidfile=/var/run/supervisord.pid

[program:mysql]
command=/usr/sbin/mysqld --user=root --datadir=/data/mysql --initialize-insecure
priority=10
autostart=true
autorestart=true
startretries=10
stdout_logfile=/var/log/supervisor/mysql.log
stderr_logfile=/var/log/supervisor/mysql_error.log

[program:chromadb]
command=python3 -m chromadb.cli.cli run --host 0.0.0.0 --port 8000 --path /data/chroma
priority=20
autostart=true
autorestart=true
startretries=10
stdout_logfile=/var/log/supervisor/chromadb.log
stderr_logfile=/var/log/supervisor/chromadb_error.log

[program:minio]
command=minio server --console-address ":9001" /data/minio
environment=MINIO_ROOT_USER="minioadmin",MINIO_ROOT_PASSWORD="minioadmin"
priority=30
autostart=true
autorestart=true
startretries=10
stdout_logfile=/var/log/supervisor/minio.log
stderr_logfile=/var/log/supervisor/minio_error.log

[program:init-db]
command=/app/init.sh
priority=35
autostart=true
autorestart=false
startretries=3
stdout_logfile=/var/log/supervisor/init-db.log
stderr_logfile=/var/log/supervisor/init-db_error.log

[program:backend]
command=/bin/bash -c "cd /app/backend && alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000"
priority=40
autostart=true
autorestart=true
startretries=10
stdout_logfile=/var/log/supervisor/backend.log
stderr_logfile=/var/log/supervisor/backend_error.log
environment=PYTHONPATH="/app/backend",MYSQL_SERVER="localhost",CHROMA_DB_HOST="localhost",MINIO_ENDPOINT="localhost:9000"

[program:frontend]
command=node /app/frontend/server.js
priority=50
autostart=true
autorestart=true
startretries=10
stdout_logfile=/var/log/supervisor/frontend.log
stderr_logfile=/var/log/supervisor/frontend_error.log
directory=/app/frontend

[program:nginx]
command=nginx -g "daemon off;"
priority=60
autostart=true
autorestart=true
startretries=10
stdout_logfile=/var/log/supervisor/nginx.log
stderr_logfile=/var/log/supervisor/nginx_error.log
EOF

# Expose ports
EXPOSE 80 3000 8000 9000 9001

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD curl -f http://localhost:80 || exit 1

# Start supervisor
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
