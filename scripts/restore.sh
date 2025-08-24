#!/bin/bash

# restore.sh - Restore script for SearXNG Docker stack
# Usage: ./restore.sh <backup_name>

set -e

BACKUP_NAME=$1
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

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if backup exists
check_backup() {
    if [ -z "$BACKUP_NAME" ]; then
        error "Please provide a backup name. Usage: ./restore.sh <backup_name>"
    fi

    if [ ! -d "$BACKUP_DIR" ]; then
        error "Backup directory not found: $BACKUP_DIR"
    fi

    log "Found backup: $BACKUP_DIR"

    # Show backup info if available
    if [ -f "$BACKUP_DIR/backup-info.txt" ]; then
        log "Backup information:"
        cat "$BACKUP_DIR/backup-info.txt"
        echo
    fi
}

# Confirm restore operation
confirm_restore() {
    warning "This will stop the current SearXNG stack and restore from backup."
    warning "Current data will be replaced with backup data."

    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Restore cancelled by user"
        exit 0
    fi
}

# Stop current stack
stop_stack() {
    log "Stopping current SearXNG stack..."

    if docker compose ps | grep -q "Up"; then
        docker compose down
        success "Stack stopped"
    else
        log "Stack was not running"
    fi
}

# Restore configuration files
restore_configs() {
    log "Restoring configuration files..."

    # Restore SearXNG configuration
    if [ -d "$BACKUP_DIR/searxng" ]; then
        log "Restoring SearXNG configuration..."
        rm -rf searxng 2>/dev/null || true
        cp -r "$BACKUP_DIR/searxng" .
        success "SearXNG configuration restored"
    fi

    # Restore docker-compose.yaml
    if [ -f "$BACKUP_DIR/docker-compose.yaml" ]; then
        log "Restoring docker-compose.yaml..."
        cp "$BACKUP_DIR/docker-compose.yaml" .
        success "docker-compose.yaml restored"
    fi

    # Restore .env file if it exists
    if [ -f "$BACKUP_DIR/.env" ]; then
        log "Restoring .env file..."
        cp "$BACKUP_DIR/.env" .
        success ".env file restored"
    fi
}

# Restore Docker volumes
restore_volumes() {
    log "Restoring Docker volumes..."

    # Remove existing volumes
    docker volume rm searxng_redis-data searxng_searxng-data 2>/dev/null || true

    # Restore Redis data
    if [ -f "$BACKUP_DIR/redis-data.tar.gz" ]; then
        log "Restoring Redis data volume..."
        docker volume create searxng_redis-data
        docker run --rm -v searxng_redis-data:/target -v "$(pwd)/$BACKUP_DIR":/backup alpine tar xzf /backup/redis-data.tar.gz -C /target
        success "Redis data volume restored"
    fi

    # Restore SearXNG data
    if [ -f "$BACKUP_DIR/searxng-data.tar.gz" ]; then
        log "Restoring SearXNG data volume..."
        docker volume create searxng_searxng-data
        docker run --rm -v searxng_searxng-data:/target -v "$(pwd)/$BACKUP_DIR":/backup alpine tar xzf /backup/searxng-data.tar.gz -C /target
        success "SearXNG data volume restored"
    fi
}

# Start the stack
start_stack() {
    log "Starting SearXNG stack..."

    docker compose up -d

    # Wait for services to be ready
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if docker compose ps | grep -q "healthy\|Up"; then
            success "Stack started successfully"
            return 0
        fi

        log "Attempt $attempt/$max_attempts - waiting for services..."
        sleep 10
        attempt=$((attempt + 1))
    done

    error "Services failed to start properly after restore"
}

# List available backups
list_backups() {
    if [ ! -d "backups" ]; then
        log "No backups directory found"
        return
    fi

    log "Available backups:"
    for backup in backups/*/; do
        if [ -d "$backup" ]; then
            backup_name=$(basename "$backup")
            backup_date="Unknown"
            if [ -f "$backup/backup-info.txt" ]; then
                backup_date=$(grep "Created:" "$backup/backup-info.txt" | cut -d: -f2- | xargs)
            fi
            echo "  - $backup_name ($backup_date)"
        fi
    done
}

# Main restore process
main() {
    if [ "$1" = "--list" ] || [ "$1" = "-l" ]; then
        list_backups
        exit 0
    fi

    log "Starting restore process..."

    check_backup
    confirm_restore
    stop_stack
    restore_configs
    restore_volumes
    start_stack

    success "Restore completed successfully!"
    log "Stack status:"
    docker compose ps
}

# Run main function
main "$@"
