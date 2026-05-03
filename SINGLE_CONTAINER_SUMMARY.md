# Single Container Architecture - Implementation Summary

## Overview

This document summarizes the changes made to convert the RAG Web UI from a multi-container Docker Compose architecture to a single-container deployment.

## Files Created

### 1. Core Files

#### `Dockerfile` (Root Directory)
- **Purpose**: Main Dockerfile for building the single-container image
- **Architecture**: Multi-stage build with three stages:
  - `base`: Ubuntu 22.04 with all system dependencies
  - `backend-builder`: Python backend with dependencies
  - `frontend-builder`: Next.js frontend build
  - `final`: Combined image with all services
- **Key Features**:
  - Installs MySQL, ChromaDB, MinIO, Python, Node.js in one image
  - Uses Supervisor for process management
  - Multi-stage build to optimize image size
  - Exposes ports: 80, 3000, 8000, 9000, 9001

#### `.dockerignore`
- **Purpose**: Optimize Docker build by excluding unnecessary files
- **Excludes**: Git files, IDE configs, node_modules, caches, logs

#### `nginx.single.conf`
- **Purpose**: Nginx configuration for single-container setup
- **Changes from original**:
  - Upstream servers point to `127.0.0.1` instead of service names
  - Added MinIO API and Console proxy locations
  - Maintains all original proxy settings for backend and frontend

#### `init.sh`
- **Purpose**: Initialization script for database and MinIO setup
- **Functions**:
  - Waits for MySQL to be ready
  - Creates database and user
  - Waits for MinIO to be ready
  - Creates MinIO bucket

### 2. Helper Scripts

#### `run.sh` (Linux/Mac)
- **Purpose**: Automated build and run script for Unix systems
- **Features**:
  - Checks for .env file
  - Builds Docker image
  - Creates necessary volumes
  - Starts container with proper configuration
  - Provides helpful output and next steps

#### `run.ps1` (Windows)
- **Purpose**: PowerShell version of run.sh for Windows users
- **Features**: Same as run.sh but with PowerShell syntax and Windows-compatible commands

### 3. Documentation

#### `README.single-container.md`
- **Purpose**: Comprehensive guide for single-container deployment
- **Contents**:
  - Quick start instructions
  - Port mappings
  - Volume management
  - Logging and debugging
  - Troubleshooting guide
  - Migration notes

#### `MIGRATION.md`
- **Purpose**: Detailed migration guide from Docker Compose
- **Contents**:
  - Benefits and considerations
  - Step-by-step migration process
  - Data backup and restore procedures
  - Troubleshooting common issues
  - Rollback instructions

#### `QUICKSTART.md`
- **Purpose**: Quick reference guide
- **Contents**:
  - 3-step quick start
  - Common commands
  - Port and volume reference tables
  - Basic troubleshooting

#### `SINGLE_CONTAINER_SUMMARY.md` (This File)
- **Purpose**: Technical summary of implementation

## Configuration Changes

### Supervisor Configuration (`/etc/supervisor/conf.d/supervisord.conf`)

Manages 7 programs in priority order:

1. **mysql** (Priority 10): MySQL database server
   - Command: `/usr/sbin/mysqld --user=root --datadir=/data/mysql --initialize-insecure`
   - Auto-restart: Yes

2. **chromadb** (Priority 20): Vector database
   - Command: `python3 -m chromadb.cli.cli run --host 0.0.0.0 --port 8000 --path /data/chroma`
   - Auto-restart: Yes

3. **minio** (Priority 30): Object storage
   - Command: `minio server --console-address ":9001" /data/minio`
   - Environment: MINIO_ROOT_USER, MINIO_ROOT_PASSWORD
   - Auto-restart: Yes

4. **init-db** (Priority 35): Database initialization
   - Command: `/app/init.sh`
   - Auto-restart: No (runs once)
   - Purpose: Initialize MySQL schema and MinIO bucket

5. **backend** (Priority 40): FastAPI backend
   - Command: `cd /app/backend && alembic upgrade head && uvicorn app.main:app --host 0.0.0.0 --port 8000`
   - Environment: PYTHONPATH, MYSQL_SERVER=localhost, CHROMA_DB_HOST=localhost, MINIO_ENDPOINT=localhost:9000
   - Auto-restart: Yes

6. **frontend** (Priority 50): Next.js frontend
   - Command: `node /app/frontend/server.js`
   - Directory: /app/frontend
   - Auto-restart: Yes

7. **nginx** (Priority 60): Reverse proxy
   - Command: `nginx -g "daemon off;"`
   - Auto-restart: Yes

### Environment Variables

Key changes for single-container mode:
```env
MYSQL_SERVER=localhost          # Was: db
CHROMA_DB_HOST=localhost        # Was: chromadb
MINIO_ENDPOINT=localhost:9000   # Was: minio:9000
```

## Docker Volumes

Four named volumes for data persistence:

| Volume Name | Mount Point | Purpose |
|------------|-------------|---------|
| rag_mysql_data | /data/mysql | MySQL database files |
| rag_chroma_data | /data/chroma | ChromaDB vector store |
| rag_minio_data | /data/minio | MinIO object storage |
| rag_uploads | /app/uploads | User uploaded documents |

## Port Mappings

| Container Port | Host Port | Service | Description |
|---------------|-----------|---------|-------------|
| 80 | 80 | Nginx | Main entry point (frontend + API proxy) |
| 3000 | - | Next.js | Internal frontend (proxied by Nginx) |
| 8000 | - | FastAPI | Internal backend (proxied by Nginx) |
| 9000 | 9000 | MinIO | MinIO API endpoint |
| 9001 | 9001 | MinIO | MinIO Console web UI |

Note: Ports 3000 and 8000 are not exposed to host directly; access via Nginx on port 80.

## Build Process

### Stage 1: Base Image
```dockerfile
FROM ubuntu:22.04 AS base
```
- Install system dependencies (curl, wget, nginx, supervisor, etc.)
- Install MySQL server
- Install Python 3.11 with pip
- Install Node.js 20 and pnpm
- Install MinIO server and client

### Stage 2: Backend Builder
```dockerfile
FROM base AS backend-builder
```
- Copy backend requirements
- Install Python packages
- Copy backend source code

### Stage 3: Frontend Builder
```dockerfile
FROM base AS frontend-builder
```
- Copy frontend package files
- Install Node dependencies
- Build Next.js application

### Stage 4: Final Image
```dockerfile
FROM base
```
- Copy built backend from stage 2
- Copy built frontend from stage 3
- Copy nginx configuration
- Copy initialization script
- Create supervisor configuration
- Set up health check
- Define CMD to start supervisor

## Startup Sequence

1. **Container starts** → Supervisor daemon launches
2. **MySQL starts** (Priority 10) → Initializes database
3. **ChromaDB starts** (Priority 20) → Starts vector database
4. **MinIO starts** (Priority 30) → Starts object storage
5. **init-db runs** (Priority 35) → Creates database schema and MinIO bucket
6. **Backend starts** (Priority 40) → Runs migrations and starts FastAPI
7. **Frontend starts** (Priority 50) → Starts Next.js server
8. **Nginx starts** (Priority 60) → Starts reverse proxy

All services run concurrently after their dependencies are ready.

## Health Check

```dockerfile
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=5 \
    CMD curl -f http://localhost:80 || exit 1
```

Checks if Nginx is responding on port 80 every 30 seconds.

## Resource Requirements

### Minimum
- **RAM**: 8GB
- **CPU**: 2 cores
- **Disk**: 20GB

### Recommended
- **RAM**: 16GB
- **CPU**: 4 cores
- **Disk**: 50GB+

### Memory Distribution (Approximate)
- MySQL: 1-2GB
- ChromaDB: 500MB-1GB
- MinIO: 500MB
- Backend: 1-2GB
- Frontend: 500MB-1GB
- Nginx: <100MB
- System overhead: 1-2GB

## Advantages

✅ **Simplified Deployment**
- Single command to start all services
- No Docker Compose dependency
- Easier CI/CD integration

✅ **Reduced Complexity**
- No inter-container networking
- Single point of monitoring
- Simplified backup procedures

✅ **Portability**
- Works on any Docker-enabled platform
- No orchestration required
- Easy to move between environments

## Limitations

⚠️ **Resource Sharing**
- All services compete for same resources
- No independent scaling
- Single point of failure

⚠️ **Image Size**
- Large image (~3-4GB)
- Longer build times
- More storage required

⚠️ **Debugging Complexity**
- Multiple services in one container
- Need to use supervisorctl for service management
- Logs mixed together

## Maintenance

### Viewing Logs
```bash
# All services
docker logs -f rag-web-ui

# Specific service
docker exec rag-web-ui cat /var/log/supervisor/backend.log
```

### Service Management
```bash
# Check status
docker exec rag-web-ui supervisorctl status

# Restart service
docker exec rag-web-ui supervisorctl restart backend

# Stop service
docker exec rag-web-ui supervisorctl stop frontend
```

### Backup
```bash
# Backup all volumes
docker run --rm -v rag_mysql_data:/data -v $(pwd):/backup alpine tar czf /backup/mysql.tar.gz -C /data .
docker run --rm -v rag_chroma_data:/data -v $(pwd):/backup alpine tar czf /backup/chroma.tar.gz -C /data .
docker run --rm -v rag_minio_data:/data -v $(pwd):/backup alpine tar czf /backup/minio.tar.gz -C /data .
docker run --rm -v rag_uploads:/data -v $(pwd):/backup alpine tar czf /backup/uploads.tar.gz -C /data .
```

## Future Improvements

Potential enhancements:
1. Add resource limits (cgroups) for each service
2. Implement graceful shutdown handling
3. Add automated backup scripts
4. Create monitoring dashboard integration
5. Add log rotation configuration
6. Implement service-specific health checks
7. Add startup dependency management improvements
8. Create update/upgrade scripts

## Testing Checklist

Before deploying to production:
- [ ] All services start successfully
- [ ] Database migrations run correctly
- [ ] MinIO bucket is created
- [ ] Frontend loads properly
- [ ] API endpoints respond
- [ ] Document upload works
- [ ] Chat functionality works
- [ ] Data persists across restarts
- [ ] Health check passes
- [ ] Logs are accessible
- [ ] Backup/restore procedure tested
- [ ] Performance is acceptable

## Support Resources

- **Quick Start**: [QUICKSTART.md](QUICKSTART.md)
- **Full Documentation**: [README.single-container.md](README.single-container.md)
- **Migration Guide**: [MIGRATION.md](MIGRATION.md)
- **Original README**: [README.md](README.md)

## Conclusion

The single-container architecture provides a simpler deployment option for RAG Web UI, especially suitable for:
- Development and testing environments
- Small-scale deployments
- Platforms without Docker Compose support
- Users who prefer simplicity over scalability

For production environments requiring high availability and scalability, the original Docker Compose or Kubernetes deployment is still recommended.
