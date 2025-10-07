# Docker B2 Backup Container

A lightweight, automated backup solution using Docker, Restic, and Backblaze B2. This container automatically backs up your data to Backblaze B2 cloud storage and can restore from the latest backup if the source directory is empty.

## ✨ Features

- **🔄 Automated Backups**: Configurable cron-based scheduling
- **☁️ Backblaze B2 Integration**: Secure, cost-effective cloud storage
- **🔐 Encryption**: End-to-end encryption via Restic
- **📦 Incremental Backups**: Efficient deduplication and compression
- **♻️ Retention Management**: Configurable snapshot retention policies
- **🔍 Health Monitoring**: Comprehensive health checks with B2 connectivity tests
- **👤 User Management**: Configurable user permissions to match host system
- **📊 Smart Restore**: Automatic restoration if backup directory is empty
- **🐳 Lightweight**: Alpine Linux base (~50MB image)
- **⚙️ Environment-Driven**: Fully configurable via environment variables

## 🏗️ Project Structure

```
docker-b2-backup/
├── src/
│   ├── backup.sh           # Main backup script with retention management
│   ├── restore.sh          # Intelligent restore script
│   ├── entrypoint.sh       # Container initialization and user management
│   └── healthcheck.sh      # Comprehensive health monitoring
├── config/
│   └── crontab            # Legacy cron configuration (now env-driven)
├── Dockerfile             # Alpine-based container definition
├── docker-compose.yml     # Production compose configuration
├── docker-compose.local.yml # Local development with user mapping
├── example.env            # Complete configuration template
├── PERMISSIONS.md         # Detailed permission management guide
└── README.md             # This file
```

## 🚀 Quick Start

### 1. Clone and Configure

```bash
git clone https://github.com/dynacylabs/docker-b2-backup.git
cd docker-b2-backup

# Copy and edit configuration
cp example.env .env
nano .env  # Configure your B2 credentials and settings
```

### 2. Configure Environment

Edit `.env` with your settings:

```bash
# Required: Backblaze B2 Configuration
RESTIC_REPOSITORY=b2:your-bucket-name:backup-path
RESTIC_PASSWORD=your-secure-restic-password
B2_ACCOUNT_ID=your-b2-account-id
B2_ACCOUNT_KEY=your-b2-account-key

# User Configuration (get with: id)
PUID=1000
PGID=1000

# Optional: Customize schedules, retention, etc.
BACKUP_SCHEDULE=0 2 * * *  # Daily at 2 AM
```

### 3. Deploy

```bash
# Local development with user mapping
docker-compose -f docker-compose.local.yml up -d

# Or production deployment
docker-compose up -d
```

### 4. Monitor

```bash
# Check container health
docker-compose ps

# View logs
docker-compose logs -f backup

# Check backup status
docker exec <container> restic snapshots
```

## ⚙️ Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `RESTIC_REPOSITORY` | Backblaze B2 repository path | `b2:my-bucket:backups/server1` |
| `RESTIC_PASSWORD` | Encryption password for backups | `your-secure-password` |
| `B2_ACCOUNT_ID` | Backblaze B2 account ID | `your-account-id` |
| `B2_ACCOUNT_KEY` | Backblaze B2 application key | `your-application-key` |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_SOURCE_DIR` | `/mnt/backup` | Directory to backup |
| `BACKUP_TEMP_DIR` | `/tmp/backup` | Temporary staging directory |
| `PUID` | `1000` | User ID for file ownership |
| `PGID` | `1000` | Group ID for file ownership |
| `BACKUP_SCHEDULE` | `0 2 * * *` | Cron schedule for backups |
| `RESTORE_CHECK_SCHEDULE` | `0 1 * * *` | Cron schedule for restore checks |
| `RESTIC_KEEP_DAILY` | `7` | Daily snapshots to retain |
| `RESTIC_KEEP_WEEKLY` | `4` | Weekly snapshots to retain |
| `RESTIC_KEEP_MONTHLY` | `6` | Monthly snapshots to retain |
| `RESTIC_KEEP_YEARLY` | `2` | Yearly snapshots to retain |
| `HEALTHCHECK_FULL_INTERVAL` | `3600` | Seconds between full B2 health checks |

### Cron Schedule Examples

```bash
# Every 6 hours
BACKUP_SCHEDULE="0 */6 * * *"

# Weekly on Sunday at 2 AM
BACKUP_SCHEDULE="0 2 * * 0"

# Twice daily (2 AM and 2 PM)
BACKUP_SCHEDULE="0 2,14 * * *"

# Monthly on the 1st at 3 AM
BACKUP_SCHEDULE="0 3 1 * *"
```

## 📁 Volume Mounting

Map your data directory to the container:

```yaml
volumes:
  - /path/to/your/data:/mnt/backup
  - /path/to/logs:/var/log  # Optional: persist logs
```

## 👤 User Permission Management

The container supports multiple user configuration methods:

### Option 1: Dynamic User Switching (Recommended)
```bash
# In .env file
PUID=1000  # Your user ID (from: id)
PGID=1000  # Your group ID

# Use local compose file
docker-compose -f docker-compose.local.yml up -d
```

### Option 2: Direct User Assignment
```bash
# Run directly as specified user
docker-compose -f docker-compose.local.yml --profile direct-user up backup-direct-user
```

See [`PERMISSIONS.md`](PERMISSIONS.md) for detailed permission management guide.

## 🏥 Health Monitoring

The container includes comprehensive health monitoring:

### Health Check Features
- **Basic checks** (every 60s): Cron, scripts, directories, environment variables
- **Full B2 checks** (configurable interval): Repository connectivity, snapshot validation, integrity checks
- **Smart rate limiting**: Minimizes B2 API calls to avoid costs and limits

### Monitoring Commands
```bash
# Check health status
docker inspect <container> | jq '.[0].State.Health'

# View health check logs
docker logs <container> | grep HEALTH

# Manual health check
docker exec <container> /src/healthcheck.sh
```

## 🔄 Backup Operations

### Automatic Operations
- **Backup**: Runs on configured schedule
- **Restore**: Automatic if backup directory is empty
- **Retention**: Old snapshots cleaned up automatically
- **Health checks**: Continuous monitoring

### Manual Operations
```bash
# Manual backup
docker exec <container> /src/backup.sh

# Manual restore
docker exec <container> /src/restore.sh

# List snapshots
docker exec <container> restic snapshots

# Repository stats
docker exec <container> restic stats

# Check repository integrity
docker exec <container> restic check
```

## 📊 Retention Policy

Default retention keeps:
- **7 daily** snapshots (last week)
- **4 weekly** snapshots (last month)
- **6 monthly** snapshots (last 6 months)  
- **2 yearly** snapshots (last 2 years)

**Maximum snapshots**: ~19 total, optimized for storage efficiency and recovery flexibility.

## 🔧 Troubleshooting

### Common Issues

**Permission denied on backup files:**
```bash
# Check and fix file ownership
sudo chown -R $(id -u):$(id -g) ./data/
```

**B2 authentication errors:**
```bash
# Verify credentials in .env file
# Check B2 account status and key permissions
```

**Container health check failing:**
```bash
# Check logs for specific error
docker logs <container>

# Run manual health check
docker exec <container> /src/healthcheck.sh
```

**Backup schedule not working:**
```bash
# Verify cron is running
docker exec <container> pgrep crond

# Check crontab
docker exec <container> crontab -l
```

### Debug Mode
```bash
# Run with debug output
docker-compose logs -f backup

# Interactive shell
docker exec -it <container> /bin/bash
```

## 💡 Best Practices

1. **Security**: Use application keys with minimal required B2 permissions
2. **Testing**: Test restore functionality regularly
3. **Monitoring**: Set up alerting on health check failures
4. **Retention**: Adjust retention policies based on your recovery needs and storage budget
5. **Updates**: Keep the container image updated for security patches

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- [Restic](https://restic.net/) - Fast, secure backup program
- [Backblaze B2](https://www.backblaze.com/b2/) - Affordable cloud storage
- [Alpine Linux](https://alpinelinux.org/) - Lightweight container base

