#!/bin/bash

# health-check.sh - Health check script for SearXNG Docker stack
# Usage: ./health-check.sh

set -e

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
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check Docker service status
check_docker() {
    log "Checking Docker service..."

    if ! systemctl is-active --quiet docker; then
        error "Docker service is not running"
        return 1
    fi

    success "Docker service is running"
    return 0
}

# Check container status
check_containers() {
    log "Checking container status..."

    local containers=("caddy" "redis" "searxng")
    local all_healthy=true

    for container in "${containers[@]}"; do
        if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q "$container.*Up"; then
            success "$container container is running"
        else
            error "$container container is not running"
            all_healthy=false
        fi
    done

    if [ "$all_healthy" = true ]; then
        success "All containers are running"
        return 0
    else
        error "Some containers are not running"
        return 1
    fi
}

# Check service connectivity
check_services() {
    log "Checking service connectivity..."

    # Check SearXNG on localhost
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200"; then
        success "SearXNG is responding on port 8080"
    else
        warning "SearXNG is not responding on port 8080"
    fi

    # Check Redis connectivity
    if docker exec redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
        success "Redis is responding to ping"
    else
        warning "Redis is not responding to ping"
    fi

    # Check if Caddy is serving content (if running on port 80/443)
    if netstat -tuln | grep -q ":80\|:443"; then
        success "Caddy is listening on HTTP/HTTPS ports"
    else
        warning "Caddy may not be listening on standard ports (check Caddyfile configuration)"
    fi
}

# Check volumes
check_volumes() {
    log "Checking Docker volumes..."

    local volumes=("searxng_caddy-data" "searxng_caddy-config" "searxng_redis-data" "searxng_searxng-data")
    local all_present=true

    for volume in "${volumes[@]}"; do
        if docker volume ls | grep -q "$volume"; then
            success "$volume exists"
        else
            warning "$volume does not exist"
            all_present=false
        fi
    done

    if [ "$all_present" = true ]; then
        success "All expected volumes are present"
        return 0
    else
        warning "Some volumes are missing"
        return 1
    fi
}

# Check disk space
check_disk_space() {
    log "Checking disk space..."

    local threshold=90
    local usage=$(df . | tail -1 | awk '{print $5}' | sed 's/%//')

    if [ "$usage" -lt "$threshold" ]; then
        success "Disk usage is ${usage}% (below ${threshold}% threshold)"
    else
        warning "Disk usage is ${usage}% (above ${threshold}% threshold)"
        return 1
    fi

    return 0
}

# Check memory usage
check_memory() {
    log "Checking memory usage..."

    local mem_info=$(free | grep Mem)
    local total=$(echo $mem_info | awk '{print $2}')
    local used=$(echo $mem_info | awk '{print $3}')
    local usage_percent=$((used * 100 / total))

    if [ "$usage_percent" -lt 90 ]; then
        success "Memory usage is ${usage_percent}%"
    else
        warning "Memory usage is high: ${usage_percent}%"
        return 1
    fi

    return 0
}

# Check container logs for errors
check_logs() {
    log "Checking container logs for recent errors..."

    local containers=("caddy" "redis" "searxng")
    local errors_found=false

    for container in "${containers[@]}"; do
        local error_count=$(docker logs --since=1h "$container" 2>&1 | grep -i -c "error\|fail\|exception" || true)

        if [ "$error_count" -eq 0 ]; then
            success "$container: No recent errors found"
        else
            warning "$container: Found $error_count error(s) in the last hour"
            errors_found=true
        fi
    done

    if [ "$errors_found" = false ]; then
        success "No recent errors found in container logs"
        return 0
    else
        warning "Some containers have recent errors"
        return 1
    fi
}

# Display system information
show_system_info() {
    log "System Information:"
    echo "===================="
    echo "Date: $(date)"
    echo "Uptime: $(uptime -p)"
    echo "Docker version: $(docker --version)"
    echo "Docker Compose version: $(docker compose version --short)"
    echo ""

    log "Container Status:"
    docker compose ps
    echo ""

    log "Resource Usage:"
    echo "Memory:"
    free -h
    echo ""
    echo "Disk:"
    df -h .
    echo ""
}

# Run comprehensive health check
run_health_check() {
    local checks_passed=0
    local total_checks=7

    log "Starting comprehensive health check..."
    echo ""

    show_system_info

    # Run all checks
    check_docker && ((checks_passed++)) || true
    check_containers && ((checks_passed++)) || true
    check_volumes && ((checks_passed++)) || true
    check_services && ((checks_passed++)) || true
    check_disk_space && ((checks_passed++)) || true
    check_memory && ((checks_passed++)) || true
    check_logs && ((checks_passed++)) || true

    echo ""
    log "Health Check Summary:"
    echo "====================="
    echo "Checks passed: $checks_passed/$total_checks"

    if [ "$checks_passed" -eq "$total_checks" ]; then
        success "All health checks passed! ✅"
        return 0
    elif [ "$checks_passed" -gt $((total_checks / 2)) ]; then
        warning "Most health checks passed, but some issues detected ⚠️"
        return 1
    else
        error "Multiple health check failures detected ❌"
        return 2
    fi
}

# Quick health check (basic status only)
quick_check() {
    log "Running quick health check..."

    if check_docker && check_containers; then
        success "Quick health check passed ✅"
        docker compose ps
        return 0
    else
        error "Quick health check failed ❌"
        return 1
    fi
}

# Main function
main() {
    case "${1:-full}" in
        "quick"|"-q"|"--quick")
            quick_check
            ;;
        "full"|"-f"|"--full"|"")
            run_health_check
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [quick|full|help]"
            echo ""
            echo "Options:"
            echo "  quick, -q, --quick    Run quick health check (containers only)"
            echo "  full, -f, --full      Run comprehensive health check (default)"
            echo "  help, -h, --help      Show this help message"
            ;;
        *)
            error "Unknown option: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
