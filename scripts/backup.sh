#!/bin/bash

# backup.sh - Backup script for SearXNG Docker stack
# Usage: ./backup.sh [backup_name]

set -e

BACKUP_NAME=${1:-"manual-$(date +%Y%m%d-%H%M%S)"}
BACKUP_DIR="backups/$BACKUP_NAME"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Create backup directory
create_backup_dir() {
    log "Creating backup directory: $BACKUP_DIR"

    if [ ! -d "backups" ]; then
        mkdir -p backups
    fi

    if [ -d "$BACKUP_DIR" ]; then
        error "Backup directory already exists: $BACKUP_DIR"
    fi

    mkdir -p "$BACKUP_DIR"
}

# Backup Docker volumes
backup_volumes() {
    log "Backing up Docker volumes..."

    # Backup Caddy data
    if docker volume ls | grep -q "searxng_caddy-data"; then
        log "Backing up Caddy data volume..."
        docker run --rm -v searxng_caddy-data:/source -v "$(pwd)/$BACKUP_DIR":/backup alpine tar czf /backup/caddy-data.tar.gz -C /source .
        success "Caddy data backed up"
    else
        log "Caddy data volume not found, skipping..."
    fi

    # Backup Redis data
    if docker volume ls | grep -q "searxng_redis-data"; then
        log "Backing up Redis data volume..."
        docker run --rm -v searxng_redis-data:/source -v "$(pwd)/$BACKUP_DIR":/backup alpine tar czf /backup/redis-data.tar.gz -C /source .
        success "Redis data backed up"
    else
        log "Redis data volume not found, skipping..."
    fi

    # Backup SearXNG data
    if docker volume ls | grep -q "searxng_searxng-data"; then
        log "Backing up SearXNG data volume..."
        docker run --rm -v searxng_searxng-data:/source -v "$(pwd)/$BACKUP_DIR":/backup alpine tar czf /backup/searxng-data.tar.gz -C /source .
        success "SearXNG data backed up"
    else
        log "SearXNG data volume not found, skipping..."
    fi

    # Backup Caddy config
    if docker volume ls | grep -q "searxng_caddy-config"; then
        log "Backing up Caddy config volume..."
        docker run --rm -v searxng_caddy-config:/source -v "$(pwd)/$BACKUP_DIR":/backup alpine tar czf /backup/caddy-config.tar.gz -C /source .
        success "Caddy config backed up"
    else
        log "Caddy config volume not found, skipping..."
    fi
}

# Backup configuration files
backup_configs() {
    log "Backing up configuration files..."

    # Backup SearXNG configuration
    if [ -d "searxng" ]; then
        cp -r searxng "$BACKUP_DIR/"
        success "SearXNG configuration backed up"
    else
        log "SearXNG config directory not found, skipping..."
    fi

    # Backup Caddyfile
    if [ -f "Caddyfile" ]; then
        cp Caddyfile "$BACKUP_DIR/"
        success "Caddyfile backed up"
    else
        log "Caddyfile not found, skipping..."
    fi

    # Backup docker-compose.yaml
    if [ -f "docker-compose.yaml" ]; then
        cp docker-compose.yaml "$BACKUP_DIR/"
        success "docker-compose.yaml backed up"
    else
        error "docker-compose.yaml not found"
    fi

    # Backup environment file if it exists
    if [ -f ".env" ]; then
        cp .env "$BACKUP_DIR/"
        success ".env file backed up"
    fi
}

# Create backup metadata
create_metadata() {
    log "Creating backup metadata..."

    cat > "$BACKUP_DIR/backup-info.txt" << EOF
Backup Information
==================
Backup Name: $BACKUP_NAME
Created: $(date)
Created By: $(whoami)
Host: $(hostname)

Docker Compose Status:
$(docker compose ps 2>/dev/null || echo "Docker Compose not available")

Docker Images:
$(docker images --filter "reference=*searxng*" --filter "reference=*caddy*" --filter "reference=*valkey*" 2>/dev/null || echo "Docker not available")

Docker Volumes:
$(docker volume ls --filter "name=searxng_*" 2>/dev/null || echo "Docker not available")
EOF

    success "Backup metadata created"
}

# Main backup process
main() {
    log "Starting backup process..."
    log "Backup name: $BACKUP_NAME"

    create_backup_dir
    backup_volumes
    backup_configs
    create_metadata

    # Calculate backup size
    BACKUP_SIZE=$(du -sh "$BACKUP_DIR" | cut -f1)

    success "Backup completed successfully!"
    log "Backup location: $BACKUP_DIR"
    log "Backup size: $BACKUP_SIZE"
    log "To restore this backup, run: ./scripts/restore.sh $BACKUP_NAME"
}

# Run main function
main "$@"
