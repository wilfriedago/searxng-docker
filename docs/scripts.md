# SearXNG Docker Deployment Scripts

This directory contains scripts for deploying and managing the SearXNG Docker stack on a VPS.

## Scripts Overview

### `deploy.sh`
Main deployment script that handles the complete deployment process:
- ✅ Creates automatic backups before deployment
- ✅ Pulls latest Docker images
- ✅ Deploys the stack with zero-downtime when possible
- ✅ Performs health checks
- ✅ Cleans up old images and backups

**Usage:**
```bash
# Normal deployment
./scripts/deploy.sh

# Force rebuild (pull images without cache)
./scripts/deploy.sh true
```

### `backup.sh`
Creates comprehensive backups of your SearXNG installation:
- ✅ Backs up all Docker volumes (Redis, SearXNG data)
- ✅ Backs up configuration files
- ✅ Creates metadata with system information
- ✅ Organizes backups with timestamps

**Usage:**
```bash
# Create automatic backup
./scripts/backup.sh

# Create named backup
./scripts/backup.sh "before-update"
```

### `restore.sh`
Restores SearXNG from a previous backup:
- ✅ Lists available backups
- ✅ Restores Docker volumes and configurations
- ✅ Confirms operations before proceeding
- ✅ Verifies stack health after restore

**Usage:**
```bash
# List available backups
./scripts/restore.sh --list

# Restore from specific backup
./scripts/restore.sh "backup-name"
```

### `health-check.sh`
Comprehensive health monitoring for your SearXNG stack:
- ✅ Checks Docker service status
- ✅ Monitors container health
- ✅ Tests service connectivity
- ✅ Monitors system resources
- ✅ Analyzes recent logs for errors

**Usage:**
```bash
# Full health check
./scripts/health-check.sh

# Quick check (containers only)
./scripts/health-check.sh quick
```

## GitHub Actions Integration

The deployment is automated through GitHub Actions. The workflow:

1. **Triggers**: Pushes to `main` branch or manual dispatch
2. **Deployment**: Copies files to VPS and runs deployment script
3. **Health Check**: Verifies successful deployment
4. **Notifications**: Reports deployment status

## Required Secrets

Configure these secrets in your GitHub repository settings:

| Secret | Description | Example |
|--------|-------------|---------|
| `VPS_SSH_KEY` | Private SSH key for VPS access | `-----BEGIN OPENSSH PRIVATE KEY-----...` |
| `VPS_HOST` | VPS hostname or IP address | `your-server.com` or `192.168.1.100` |
| `VPS_USER` | SSH username for VPS | `ubuntu` or `deploy` |
| `VPS_DEPLOY_PATH` | Deployment directory on VPS | `/opt/searxng` |

## VPS Setup Requirements

### 1. Install Docker and Docker Compose
```bash
# Ubuntu/Debian
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### 2. Setup SSH Key Authentication
```bash
# On your local machine, generate SSH key if needed
ssh-keygen -t ed25519 -C "github-actions@yourdomain.com"

# Copy public key to VPS
ssh-copy-id user@your-vps

# Add private key to GitHub Secrets as VPS_SSH_KEY
```

### 3. Create Deployment Directory
```bash
# On VPS
sudo mkdir -p /opt/searxng
sudo chown $USER:$USER /opt/searxng
```

### 4. Environment Configuration
Create `.env` file on VPS with your configuration:
```bash
# /opt/searxng/.env
SEARXNG_HOSTNAME=your-domain.com
```

## Monitoring and Maintenance

### Automatic Backups
Set up a cron job for regular backups:
```bash
# Add to crontab (daily backup at 2 AM)
0 2 * * * cd /opt/searxng && ./scripts/backup.sh "daily-$(date +%Y%m%d)" > /var/log/searxng-backup.log 2>&1
```

### Log Monitoring
Monitor application logs:
```bash
# View real-time logs
docker compose logs -f

# Check specific service
docker compose logs -f searxng
```

### Resource Monitoring
Regular health checks:
```bash
# Add to crontab (every 30 minutes)
*/30 * * * * cd /opt/searxng && ./scripts/health-check.sh quick > /var/log/searxng-health.log 2>&1
```

## Troubleshooting

### Common Issues

**1. Deployment fails with permission errors**
```bash
# Ensure scripts are executable
chmod +x scripts/*.sh

# Check file ownership
sudo chown -R $USER:$USER /opt/searxng
```

**2. Services fail to start**
```bash
# Check logs
docker compose logs

# Verify configuration
./scripts/health-check.sh
```

**3. SSL certificate issues**
```bash
# Check Caddy logs
docker compose logs caddy

# Verify domain DNS
nslookup your-domain.com
```

**4. Memory/disk space issues**
```bash
# Clean up Docker system
docker system prune -a

# Check disk usage
df -h
```

### Recovery Procedures

**1. Rollback to previous backup**
```bash
./scripts/restore.sh --list
./scripts/restore.sh "backup-name"
```

**2. Manual service restart**
```bash
docker compose down
docker compose up -d
```

**3. Force rebuild**
```bash
./scripts/deploy.sh true
```

## Security Best Practices

1. **SSH Security**: Use key-based authentication only
2. **Firewall**: Configure UFW to limit exposed ports
3. **Updates**: Keep VPS system updated
4. **Monitoring**: Set up log monitoring and alerts
5. **Backups**: Test restore procedures regularly

## Support

For issues with the deployment scripts or GitHub Actions workflow, check:

1. GitHub Actions logs in the repository
2. VPS system logs: `/var/log/syslog`
3. Application logs: `docker compose logs`
4. Health check output: `./scripts/health-check.sh`
