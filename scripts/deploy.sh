#!/bin/bash

# deploy.sh - Main deployment script for SearXNG Docker stack
# Usage: ./deploy.sh [force_rebuild]

set -e

FORCE_REBUILD=${1:-false}
BACKUP_DIR="backups/$(date +%Y%m%d-%H%M%S)"
LOG_FILE="deploy.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"
}

# Check if Docker and Docker Compose are installed
check_dependencies() {
    log "Checking dependencies..."

    if ! command -v docker &> /dev/null; then
        error "Docker is not installed"
    fi

    if ! command -v docker compose &> /dev/null; then
        error "Docker Compose is not installed"
    fi

    success "Dependencies check passed"
}

# Create backup before deployment
create_backup() {
    log "Creating backup..."

    if [ ! -d "backups" ]; then
        mkdir -p backups
    fi

    mkdir -p "$BACKUP_DIR"

    # Backup volumes data if they exist
    if docker volume ls | grep -q "searxng_caddy-data"; then
        log "Backing up Caddy data..."
        docker run --rm -v searxng_caddy-data:/source -v "$(pwd)/$BACKUP_DIR":/backup alpine tar czf /backup/caddy-data.tar.gz -C /source .
    fi

    if docker volume ls | grep -q "searxng_redis-data"; then
        log "Backing up Redis data..."
        docker run --rm -v searxng_redis-data:/source -v "$(pwd)/$BACKUP_DIR":/backup alpine tar czf /backup/redis-data.tar.gz -C /source .
    fi

    if docker volume ls | grep -q "searxng_searxng-data"; then
        log "Backing up SearXNG data..."
        docker run --rm -v searxng_searxng-data:/source -v "$(pwd)/$BACKUP_DIR":/backup alpine tar czf /backup/searxng-data.tar.gz -C /source .
    fi

    # Backup configuration files
    cp -r searxng "$BACKUP_DIR/" 2>/dev/null || warning "SearXNG config directory not found"
    cp Caddyfile "$BACKUP_DIR/" 2>/dev/null || warning "Caddyfile not found"
    cp docker-compose.yaml "$BACKUP_DIR/" || error "docker-compose.yaml not found"

    success "Backup created at $BACKUP_DIR"
}

# Pull latest images
pull_images() {
    log "Pulling latest Docker images..."

    if [ "$FORCE_REBUILD" = "true" ]; then
        log "Force rebuild requested - pulling images without cache..."
        docker compose pull --no-cache
    else
        docker compose pull
    fi

    success "Images pulled successfully"
}

# Deploy the stack
deploy_stack() {
    log "Deploying SearXNG stack..."

    # Stop current stack if running
    if docker compose ps | grep -q "Up"; then
        log "Stopping current stack..."
        docker compose down
    fi

    # Start the new stack
    log "Starting new stack..."
    docker compose up -d

    success "Stack deployed successfully"
}

# Cleanup old images and containers
cleanup() {
    log "Cleaning up old images and containers..."

    # Remove unused images
    docker image prune -f

    # Remove old backups (keep last 5)
    if [ -d "backups" ]; then
        ls -1t backups/ | tail -n +6 | xargs -I {} rm -rf "backups/{}" 2>/dev/null || true
    fi

    success "Cleanup completed"
}

# Wait for services to be healthy
wait_for_services() {
    log "Waiting for services to be healthy..."

    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if docker compose ps | grep -q "healthy\|Up"; then
            success "Services are running"
            return 0
        fi

        log "Attempt $attempt/$max_attempts - waiting for services..."
        sleep 10
        attempt=$((attempt + 1))
    done

    error "Services failed to start properly"
}

# Main deployment process
main() {
    log "Starting deployment process..."

    check_dependencies
    create_backup
    pull_images
    deploy_stack
    wait_for_services
    cleanup

    success "Deployment completed successfully!"
    log "Backup available at: $BACKUP_DIR"
    log "Check service status with: docker compose ps"
    log "View logs with: docker compose logs -f"
}

# Run main function
main "$@"
