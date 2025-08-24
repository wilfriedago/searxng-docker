#!/bin/bash

# health-check.sh - Health check script for SearXNG Docker stack
# Usage: ./health-check.sh [quick|full|help] [--verbose]

set -e

# Default behavior: warnings don't fail the check in CI
CI_MODE=${CI:-false}
VERBOSE=${2:-false}

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
    local service_issues=0

    # Check SearXNG on localhost
    if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 | grep -q "200"; then
        success "SearXNG is responding on port 8080"
    else
        warning "SearXNG is not responding on port 8080"
        ((service_issues++))
    fi

    # Check Redis connectivity
    if docker exec redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
        success "Redis is responding to ping"
    else
        warning "Redis is not responding to ping"
        ((service_issues++))
    fi

    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -E ":80\s|:443\s|\*:80|\*:443"; then
            success "Caddy is listening on HTTP/HTTPS ports"
        else
            warning "Caddy may not be listening on standard ports (check Caddyfile configuration)"
            ((service_issues++))
        fi
    else
        warning "Cannot verify Caddy port configuration (ss not available)"
        if [ "$CI_MODE" = "true" ]; then
            log "Skipping port check in CI mode"
        else
            ((service_issues++))
        fi
    fi

    # In CI mode, don't fail on service connectivity issues
    if [ "$CI_MODE" = "true" ] && [ "$service_issues" -gt 0 ]; then
        warning "Service connectivity issues detected but ignoring in CI mode"
        return 0
    fi

    return $service_issues
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

# Check container logs for errors (improved)
check_logs() {
    log "Checking container logs for recent errors..."

    local containers=("caddy" "redis" "searxng")
    local critical_errors=0

    for container in "${containers[@]}"; do
        # Look for critical errors only, ignore common startup messages
        local error_count=$(docker logs --since=1h "$container" 2>&1 | \
            grep -i -E "fatal|critical|panic|out of memory|connection refused|bind.*failed" | \
            grep -v -E "starting|started|listening|ready" | \
            wc -l || echo "0")

        if [ "$error_count" -eq 0 ]; then
            success "$container: No critical errors found"
        else
            if [ "$error_count" -gt 3 ]; then
                error "$container: Found $error_count critical error(s) in the last hour"
                ((critical_errors++))
            else
                warning "$container: Found $error_count minor error(s) in the last hour"
                if [ "$VERBOSE" = "true" ] || [ "$2" = "--verbose" ]; then
                    log "Recent errors for $container:"
                    docker logs --since=1h "$container" 2>&1 | grep -i -E "error|fail|exception" | tail -3
                fi
            fi
        fi
    done

    if [ "$critical_errors" -eq 0 ]; then
        success "No critical errors found in container logs"
        return 0
    else
        error "Critical errors found in container logs"
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
    local critical_failures=0
    local warnings=0
    local total_checks=7

    log "Starting comprehensive health check..."
    if [ "$CI_MODE" = "true" ]; then
        log "Running in CI mode - warnings won't cause failure"
    fi
    echo ""

    show_system_info

    # Run all checks and count failures vs warnings
    check_docker || ((critical_failures++))
    check_containers || ((critical_failures++))
    check_volumes || ((warnings++))
    check_services || ((warnings++))
    check_disk_space || ((warnings++))
    check_memory || ((warnings++))
    check_logs || ((warnings++))

    local checks_passed=$((total_checks - critical_failures - warnings))

    echo ""
    log "Health Check Summary:"
    echo "====================="
    echo "Checks passed: $checks_passed/$total_checks"
    echo "Critical failures: $critical_failures"
    echo "Warnings: $warnings"

    if [ "$critical_failures" -eq 0 ]; then
        if [ "$warnings" -eq 0 ]; then
            success "All health checks passed! ✅"
            return 0
        else
            if [ "$CI_MODE" = "true" ]; then
                success "Health check passed with warnings (CI mode) ✅⚠️"
                return 0
            else
                warning "Health check passed but with warnings ⚠️"
                return 1
            fi
        fi
    else
        error "Critical health check failures detected ❌"
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
    # Check for verbose flag
    if [[ " $* " =~ " --verbose " ]] || [[ " $* " =~ " -v " ]]; then
        VERBOSE=true
    fi

    case "${1:-full}" in
        "quick"|"-q"|"--quick")
            quick_check
            ;;
        "full"|"-f"|"--full"|"")
            run_health_check
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [quick|full|help] [--verbose]"
            echo ""
            echo "Options:"
            echo "  quick, -q, --quick    Run quick health check (containers only)"
            echo "  full, -f, --full      Run comprehensive health check (default)"
            echo "  --verbose, -v         Show detailed error logs"
            echo "  help, -h, --help      Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  CI=true              Run in CI mode (warnings don't fail)"
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
