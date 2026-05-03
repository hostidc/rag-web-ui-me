# RAG Web UI - Single Container Build and Run Script (PowerShell)

$ErrorActionPreference = "Stop"

$IMAGE_NAME = "rag-web-ui"
$CONTAINER_NAME = "rag-web-ui"
$TAG = "latest"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "RAG Web UI - Single Container Deployment" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# Check if .env file exists
if (-not (Test-Path ".env")) {
    Write-Host "⚠️  Warning: .env file not found!" -ForegroundColor Yellow
    Write-Host "Creating .env from .env.example..." -ForegroundColor Yellow
    Copy-Item ".env.example" ".env"
    Write-Host "✅ Created .env file. Please edit it with your configuration before running." -ForegroundColor Green
    Write-Host ""
    exit 1
}

# Build the Docker image
Write-Host "📦 Building Docker image..." -ForegroundColor Cyan
docker build -t "${IMAGE_NAME}:${TAG}" .
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Docker build failed!" -ForegroundColor Red
    exit 1
}
Write-Host "✅ Docker image built successfully!" -ForegroundColor Green
Write-Host ""

# Check if container is already running
$existingContainer = docker ps -a --format '{{.Names}}' | Where-Object { $_ -eq $CONTAINER_NAME }
if ($existingContainer) {
    Write-Host "⚠️  Container '${CONTAINER_NAME}' already exists." -ForegroundColor Yellow
    $response = Read-Host "Do you want to remove it and create a new one? (y/n)"
    if ($response -eq 'y' -or $response -eq 'Y') {
        Write-Host "🗑️  Stopping and removing existing container..." -ForegroundColor Cyan
        docker stop $CONTAINER_NAME 2>$null
        docker rm $CONTAINER_NAME 2>$null
        Write-Host "✅ Existing container removed." -ForegroundColor Green
    } else {
        Write-Host "❌ Aborted." -ForegroundColor Red
        exit 0
    }
}

# Create volumes if they don't exist
Write-Host "📁 Creating Docker volumes..." -ForegroundColor Cyan
docker volume create rag_mysql_data 2>$null | Out-Null
docker volume create rag_chroma_data 2>$null | Out-Null
docker volume create rag_minio_data 2>$null | Out-Null
docker volume create rag_uploads 2>$null | Out-Null
Write-Host "✅ Volumes created/verified." -ForegroundColor Green
Write-Host ""

# Run the container
Write-Host "🚀 Starting container..." -ForegroundColor Cyan
docker run -d `
  --name $CONTAINER_NAME `
  -p 80:80 `
  -p 9000:9000 `
  -p 9001:9001 `
  -v rag_mysql_data:/data/mysql `
  -v rag_chroma_data:/data/chroma `
  -v rag_minio_data:/data/minio `
  -v rag_uploads:/app/uploads `
  --env-file .env `
  "${IMAGE_NAME}:${TAG}"

Write-Host ""
Write-Host "✅ Container started successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Access URLs:" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "🌐 Frontend:        http://localhost" -ForegroundColor White
Write-Host "📚 API Docs:        http://localhost/redoc" -ForegroundColor White
Write-Host "💾 MinIO Console:   http://localhost:9001 (minioadmin/minioadmin)" -ForegroundColor White
Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Useful Commands:" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "View logs:          docker logs -f $CONTAINER_NAME" -ForegroundColor White
Write-Host "Stop container:     docker stop $CONTAINER_NAME" -ForegroundColor White
Write-Host "Remove container:   docker rm $CONTAINER_NAME" -ForegroundColor White
Write-Host "Enter container:    docker exec -it $CONTAINER_NAME bash" -ForegroundColor White
Write-Host ""
Write-Host "Waiting for services to start..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

# Check if container is running
$runningContainer = docker ps --format '{{.Names}}' | Where-Object { $_ -eq $CONTAINER_NAME }
if ($runningContainer) {
    Write-Host "✅ All services are running!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Note: First startup may take a few minutes to initialize databases." -ForegroundColor Yellow
    Write-Host "Check logs with: docker logs -f $CONTAINER_NAME" -ForegroundColor White
} else {
    Write-Host "❌ Container failed to start. Check logs:" -ForegroundColor Red
    docker logs $CONTAINER_NAME
    exit 1
}
