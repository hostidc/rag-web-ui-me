# RAG Web UI - Single Container Deployment

## 概述

本项目已改为单容器 Docker 架构，所有服务（MySQL、ChromaDB、MinIO、Backend、Frontend、Nginx）都在一个容器中运行，通过 Supervisor 管理进程。

## 快速开始

### 1. 准备环境变量

复制环境变量模板并配置：

```bash
cp .env.example .env
```

编辑 `.env` 文件，设置必要的配置项，特别是：
- `OPENAI_API_KEY` 或其他 LLM 提供商的 API Key
- `SECRET_KEY` 用于 JWT 签名

### 2. 构建 Docker 镜像

```bash
docker build -t rag-web-ui:latest .
```

### 3. 运行容器

```bash
docker run -d \
  --name rag-web-ui \
  -p 80:80 \
  -p 9000:9000 \
  -p 9001:9001 \
  -v rag_mysql_data:/data/mysql \
  -v rag_chroma_data:/data/chroma \
  -v rag_minio_data:/data/minio \
  -v rag_uploads:/app/uploads \
  --env-file .env \
  rag-web-ui:latest
```

### 4. 访问应用

- **前端应用**: http://localhost
- **API 文档**: http://localhost/redoc
- **MinIO 控制台**: http://localhost:9001 (用户名/密码: minioadmin/minioadmin)

## 端口说明

- `80`: Nginx HTTP 服务（前端和 API 代理）
- `3000`: Next.js 前端服务（内部）
- `8000`: FastAPI 后端服务（内部）
- `9000`: MinIO API
- `9001`: MinIO 控制台

## 数据持久化

使用 Docker volumes 持久化以下数据：
- `rag_mysql_data`: MySQL 数据库文件
- `rag_chroma_data`: ChromaDB 向量数据
- `rag_minio_data`: MinIO 对象存储
- `rag_uploads`: 用户上传的文档

## 查看日志

```bash
# 查看所有日志
docker logs -f rag-web-ui

# 查看特定服务日志
docker exec rag-web-ui cat /var/log/supervisor/backend.log
docker exec rag-web-ui cat /var/log/supervisor/frontend.log
docker exec rag-web-ui cat /var/log/supervisor/mysql.log
```

## 进入容器调试

```bash
docker exec -it rag-web-ui /bin/bash
```

## 停止和删除容器

```bash
docker stop rag-web-ui
docker rm rag-web-ui
```

## 清理数据卷（谨慎操作）

```bash
docker volume rm rag_mysql_data rag_chroma_data rag_minio_data rag_uploads
```

## 架构说明

容器内运行的服务：
1. **MySQL 8.0**: 关系型数据库，存储用户、知识库、对话等元数据
2. **ChromaDB**: 向量数据库，存储文档嵌入
3. **MinIO**: 对象存储，存储上传的文档文件
4. **FastAPI Backend**: Python 后端服务，处理业务逻辑
5. **Next.js Frontend**: React 前端应用
6. **Nginx**: 反向代理，统一入口

所有服务通过 Supervisor 进行进程管理，确保服务的自动重启和监控。

## 注意事项

⚠️ **重要提示**：
- 此单容器架构适合开发和测试环境
- 生产环境建议使用 Kubernetes 或 Docker Compose 进行多容器部署
- 单个容器资源占用较大，建议至少分配 8GB RAM
- 首次启动可能需要几分钟时间初始化数据库和服务

## 故障排查

### 容器启动失败

1. 检查日志：
   ```bash
   docker logs rag-web-ui
   ```

2. 检查 Supervisor 状态：
   ```bash
   docker exec rag-web-ui supervisorctl status
   ```

3. 检查各服务日志：
   ```bash
   docker exec rag-web-ui ls -la /var/log/supervisor/
   ```

### 数据库连接问题

确保 MySQL 已正确初始化：
```bash
docker exec rag-web-ui mysql -u root -e "SHOW DATABASES;"
```

### MinIO 访问问题

检查 MinIO 服务状态：
```bash
docker exec rag-web-ui curl http://localhost:9000/minio/health/live
```

## 从 Docker Compose 迁移

如果您之前使用 Docker Compose，可以按以下步骤迁移：

1. 备份数据：
   ```bash
   docker-compose down
   ```

2. 构建新镜像：
   ```bash
   docker build -t rag-web-ui:latest .
   ```

3. 启动新容器（数据会自动从旧 volumes 迁移）

4. 验证应用正常运行后，可以删除旧的 Docker Compose 配置
