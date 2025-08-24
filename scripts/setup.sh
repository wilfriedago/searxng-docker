#!/bin/bash

# setup.sh - Quick setup script for SearXNG Docker
# Usage: ./setup.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${BLUE}[INFO]${NC} $1"
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

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first: https://docs.docker.com/install/"
    fi

    if ! command -v docker compose &> /dev/null; then
        error "Docker Compose is not installed"
    fi

    success "Prerequisites check passed"
}

# Setup environment file
setup_environment() {
    log "Setting up environment configuration..."

    if [ -f ".env" ]; then
        warning ".env file already exists, skipping creation"
        return
    fi

    # Copy example environment file
    cp .env.example .env

    # Prompt for hostname
    read -p "Enter your domain name (or 'localhost' for local testing): " hostname
    hostname=${hostname:-localhost}

    # Update hostname
    sed -i.bak "s/SEARXNG_HOSTNAME=localhost/SEARXNG_HOSTNAME=$hostname/" .env

    # Clean up backup file
    rm -f .env.bak

    success "Environment file created at .env"
}

# Generate secret key
generate_secret() {
    log "Generating secret key..."

    if grep -q "ultrasecretkey" searxng/settings.yml; then
        # Generate random secret key
        if command -v openssl &> /dev/null; then
            secret=$(openssl rand -hex 32)
        else
            # Fallback for systems without openssl
            secret=$(head -c 32 /dev/urandom | xxd -p -c 32)
        fi

        # Replace in settings file
        sed -i "s|ultrasecretkey|$secret|g" searxng/settings.yml

        success "Secret key generated and updated in searxng/settings.yml"
    else
        log "Secret key already configured"
    fi
}

# Make scripts executable
setup_scripts() {
    log "Setting up deployment scripts..."

    chmod +x scripts/*.sh

    success "Deployment scripts are now executable"
}

# Start services
start_services() {
    log "Starting SearXNG services..."

    docker compose up -d

    success "Services started successfully"

    # Wait a moment for services to initialize
    sleep 5

    # Run health check
    if [ -f "scripts/health-check.sh" ]; then
        log "Running health check..."
        ./scripts/health-check.sh quick
    fi
}

# Display completion message
show_completion() {
    echo ""
    success "🎉 SearXNG setup completed!"
    echo ""
    echo "Next steps:"
    echo "==========="

    # Get hostname from .env
    if [ -f ".env" ]; then
        hostname=$(grep SEARXNG_HOSTNAME .env | cut -d= -f2)
        if [ "$hostname" = "localhost" ]; then
            echo "• Access SearXNG at: http://localhost:8080"
        else
            echo "• Access SearXNG at: https://$hostname"
        fi
    fi

    echo "• View logs: docker compose logs -f"
    echo "• Check status: docker compose ps"
    echo "• Health check: ./scripts/health-check.sh"
    echo "• Create backup: ./scripts/backup.sh"
    echo ""
    echo "Configuration files:"
    echo "• Environment: .env"
    echo "• SearXNG settings: searxng/settings.yml"
    echo ""
    echo "For VPS deployment setup, see: scripts/README.md"
    echo ""
}

# Main setup process
main() {
    echo "========================================"
    echo "     SearXNG Docker Setup Script"
    echo "========================================"
    echo ""

    check_prerequisites
    setup_environment
    generate_secret
    setup_scripts
    start_services
    show_completion
}

# Run main function
main "$@"
