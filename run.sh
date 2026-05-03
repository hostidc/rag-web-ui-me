#!/bin/bash

# RAG Web UI - Single Container Build and Run Script

set -e

IMAGE_NAME="rag-web-ui"
CONTAINER_NAME="rag-web-ui"
TAG="latest"

echo "========================================="
echo "RAG Web UI - Single Container Deployment"
echo "========================================="
echo ""

# Check if .env file exists
if [ ! -f .env ]; then
    echo "⚠️  Warning: .env file not found!"
    echo "Creating .env from .env.example..."
    cp .env.example .env
    echo "✅ Created .env file. Please edit it with your configuration before running."
    echo ""
    exit 1
fi

# Build the Docker image
echo "📦 Building Docker image..."
docker build -t ${IMAGE_NAME}:${TAG} .
echo "✅ Docker image built successfully!"
echo ""

# Check if container is already running
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "⚠️  Container '${CONTAINER_NAME}' already exists."
    read -p "Do you want to remove it and create a new one? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️  Stopping and removing existing container..."
        docker stop ${CONTAINER_NAME} 2>/dev/null || true
        docker rm ${CONTAINER_NAME} 2>/dev/null || true
        echo "✅ Existing container removed."
    else
        echo "❌ Aborted."
        exit 0
    fi
fi

# Create volumes if they don't exist
echo "📁 Creating Docker volumes..."
docker volume create rag_mysql_data 2>/dev/null || true
docker volume create rag_chroma_data 2>/dev/null || true
docker volume create rag_minio_data 2>/dev/null || true
docker volume create rag_uploads 2>/dev/null || true
echo "✅ Volumes created/verified."
echo ""

# Run the container
echo "🚀 Starting container..."
docker run -d \
  --name ${CONTAINER_NAME} \
  -p 80:80 \
  -p 9000:9000 \
  -p 9001:9001 \
  -v rag_mysql_data:/data/mysql \
  -v rag_chroma_data:/data/chroma \
  -v rag_minio_data:/data/minio \
  -v rag_uploads:/app/uploads \
  --env-file .env \
  ${IMAGE_NAME}:${TAG}

echo ""
echo "✅ Container started successfully!"
echo ""
echo "========================================="
echo "Access URLs:"
echo "========================================="
echo "🌐 Frontend:        http://localhost"
echo "📚 API Docs:        http://localhost/redoc"
echo "💾 MinIO Console:   http://localhost:9001 (minioadmin/minioadmin)"
echo ""
echo "========================================="
echo "Useful Commands:"
echo "========================================="
echo "View logs:          docker logs -f ${CONTAINER_NAME}"
echo "Stop container:     docker stop ${CONTAINER_NAME}"
echo "Remove container:   docker rm ${CONTAINER_NAME}"
echo "Enter container:    docker exec -it ${CONTAINER_NAME} /bin/bash"
echo ""
echo "Waiting for services to start..."
sleep 5

# Check if container is running
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "✅ All services are running!"
    echo ""
    echo "Note: First startup may take a few minutes to initialize databases."
    echo "Check logs with: docker logs -f ${CONTAINER_NAME}"
else
    echo "❌ Container failed to start. Check logs:"
    docker logs ${CONTAINER_NAME}
    exit 1
fi
