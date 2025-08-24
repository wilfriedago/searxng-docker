#!/bin/bash

# deploy.sh - Main deployment script for SearXNG Docker stack with Git integration
# Usage: ./deploy.sh [force_rebuild] [skip_git]

set -e

FORCE_REBUILD=${1:-false}
SKIP_GIT=${2:-false}
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

# Update code from git repository
update_code() {
    if [ "$SKIP_GIT" = "true" ]; then
        log "Skipping git operations as requested"
        return 0
    fi

    log "📥 Updating code from git repository..."

    # Check if we're in a git repository
    if [ ! -d ".git" ]; then
        error "Not in a git repository. Please ensure you're in the project root."
    fi

    # Get current branch
    CURRENT_BRANCH=$(git branch --show-current)
    log "Current branch: $CURRENT_BRANCH"

    # Stash any local changes
    if ! git diff --quiet || ! git diff --cached --quiet; then
        warning "Local changes detected. Stashing them..."
        git stash push -m "Auto-stash before deployment $(date)"
    fi

    # Ensure we're on the main branch
    if [ "$CURRENT_BRANCH" != "main" ]; then
        log "Switching to main branch..."
        git checkout main || error "Failed to checkout main branch"
    fi

    # Pull latest changes
    log "Pulling latest changes from origin..."
    if ! git pull origin main --rebase --autostash --no-edit; then
        error "Failed to pull changes from git repository"
    fi

    # Get commit information
    LATEST_COMMIT=$(git log -1 --oneline)
    COMMIT_HASH=$(git rev-parse --short HEAD)
    COMMIT_AUTHOR=$(git log -1 --pretty=format:'%an')
    COMMIT_DATE=$(git log -1 --pretty=format:'%cd' --date=short)

    log "📋 Latest commit: $LATEST_COMMIT"
    log "👤 Author: $COMMIT_AUTHOR"
    log "📅 Date: $COMMIT_DATE"
    log "🔗 Commit hash: $COMMIT_HASH"

    # Make scripts executable (in case they weren't committed as executable)
    chmod +x scripts/*.sh 2>/dev/null || warning "No scripts found in scripts/ directory"

    success "Code updated successfully"
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

    if ! command -v git &> /dev/null; then
        error "Git is not installed"
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

    # Backup git information
    echo "Git commit: $(git rev-parse HEAD)" > "$BACKUP_DIR/git-info.txt"
    echo "Branch: $(git branch --show-current)" >> "$BACKUP_DIR/git-info.txt"
    echo "Date: $(date)" >> "$BACKUP_DIR/git-info.txt"

    # Backup volumes data if they exist
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

# Show deployment summary
show_summary() {
    log "📊 Deployment Summary:"
    log "===================="

    if [ "$SKIP_GIT" != "true" ]; then
        log "🔗 Deployed commit: $(git rev-parse --short HEAD)"
        log "👤 Author: $(git log -1 --pretty=format:'%an')"
        log "📅 Commit date: $(git log -1 --pretty=format:'%cd' --date=short)"
        log "📝 Message: $(git log -1 --pretty=format:'%s')"
    fi

    log "💾 Backup location: $BACKUP_DIR"
    log "🔧 Force rebuild: $FORCE_REBUILD"
    log "⏰ Deployment time: $(date)"

    echo ""
    log "📋 Next steps:"
    log "  • Check service status: docker compose ps"
    log "  • View logs: docker compose logs -f"
    log "  • Health check: ./scripts/health-check.sh"
}

# Main deployment process
main() {
    log "🚀 Starting deployment process..."
    log "Parameters: force_rebuild=$FORCE_REBUILD, skip_git=$SKIP_GIT"

    check_dependencies
    update_code
    create_backup
    pull_images
    deploy_stack
    wait_for_services
    cleanup
    show_summary

    success "✅ Deployment completed successfully!"
}

# Handle script arguments
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [force_rebuild] [skip_git]"
    echo ""
    echo "Arguments:"
    echo "  force_rebuild  - Set to 'true' to force rebuild containers (default: false)"
    echo "  skip_git      - Set to 'true' to skip git operations (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                    # Normal deployment"
    echo "  $0 true               # Force rebuild containers"
    echo "  $0 false true         # Skip git operations"
    echo "  $0 true false         # Force rebuild with git update"
    exit 0
fi

# Run main function
main "$@"
