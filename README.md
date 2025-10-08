# Docker B2 Backup Container

A lightweight, automated backup solution using Docker, Restic, and Backblaze B2. This container automatically backs up your data to Backblaze B2 cloud storage with a simple scheduler (no cron needed!) and comprehensive health monitoring.

## ✨ Features

- **🚀 Startup Backup**: Always runs backup immediately when container starts
- **🔄 Auto-Restore**: Checks and restores if directory is empty on startup
- **⏰ Simple Scheduler**: Cron-like syntax without the complexity (no cron daemon!)
- **☁️ Backblaze B2 Integration**: Secure, cost-effective cloud storage
- **🔐 Encryption**: End-to-end encryption via Restic
- **📦 Incremental Backups**: Efficient deduplication and compression
- **♻️ Retention Management**: Configurable snapshot retention policies
- **🏥 Comprehensive Health Monitoring**: Automatic failure detection with detailed status
- **👤 User Management**: Configurable user permissions to match host system
- **🐳 Lightweight**: Alpine Linux base (~50MB image)
- **⚙️ Environment-Driven**: Fully configurable via environment variables

## 🏗️ Project Structure

```
docker-b2-backup/
├── src/
│   ├── backup.sh           # Main backup script with retention management
│   ├── restore.sh          # Intelligent restore script
│   ├── scheduler.sh        # Simple scheduler (replaces cron)
│   ├── entrypoint.sh       # Container initialization
│   └── healthcheck.sh      # Comprehensive health monitoring with failure detection
├── Dockerfile              # Alpine-based container definition
├── docker-compose.yml      # Production compose configuration
├── example.env             # Complete configuration template
└── README.md              # This file
```

## 🔧 How It Works

This container uses a **simple scheduler script** instead of cron for maximum reliability:

1. **On Startup:**
   - Checks if backup directory is empty → restores if needed
   - Runs initial backup immediately
   - Starts scheduler loop

2. **During Operation:**
   - Checks every 60 seconds if current time matches schedule
   - Runs backup if schedule matches
   - Runs restore check if schedule matches (only if directory is empty)

3. **Health Monitoring:**
   - Detects backup/restore failures within 60 seconds
   - Marks container UNHEALTHY automatically
   - Enables automatic restart with autoheal

**Why No Cron?**
- ✅ Simpler - no crontab configuration
- ✅ More reliable - no permission issues
- ✅ Better visibility - all logs in stdout
- ✅ Easier debugging - see exactly what's happening
- ✅ Same flexibility - supports cron syntax

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
# Check container status and health
docker-compose ps

# View logs in real-time
docker-compose logs -f

# Check scheduler log
docker-compose exec backup cat /var/log/scheduler.log

# Check backup log
docker-compose exec backup cat /var/log/backup.log

# View snapshots
docker-compose exec backup restic snapshots
```

**Note:** The container will automatically:
- Check if restore is needed on startup
- Run an initial backup immediately
- Then follow the configured schedule

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
| `BACKUP_SOURCE_DIR` | `/backup` | Directory to backup |
| `BACKUP_TEMP_DIR` | `/tmp/backup` | Temporary staging directory |
| `PUID` | `1000` | User ID for file ownership |
| `PGID` | `1000` | Group ID for file ownership |
| `BACKUP_SCHEDULE` | `0 2 * * *` | Schedule for backups (cron syntax) |
| `RESTORE_CHECK_SCHEDULE` | `0 1 * * *` | Schedule for restore checks (cron syntax) |
| `RESTIC_KEEP_DAILY` | `7` | Daily snapshots to retain |
| `RESTIC_KEEP_WEEKLY` | `4` | Weekly snapshots to retain |
| `RESTIC_KEEP_MONTHLY` | `6` | Monthly snapshots to retain |
| `RESTIC_KEEP_YEARLY` | `2` | Yearly snapshots to retain |
| `HEALTHCHECK_FULL_INTERVAL` | `3600` | Seconds between full B2 health checks |

### Cron Schedule Examples

The scheduler uses familiar cron-like syntax:

```bash
# Every 5 minutes
BACKUP_SCHEDULE="*/5 * * * *"

# Every hour
BACKUP_SCHEDULE="0 * * * *"

# Every 6 hours
BACKUP_SCHEDULE="0 */6 * * *"

# Daily at 2:30 AM
BACKUP_SCHEDULE="30 2 * * *"

# Weekly on Sunday at 2 AM
BACKUP_SCHEDULE="0 2 * * 0"

# Twice daily (2 AM and 2 PM)
BACKUP_SCHEDULE="0 2,14 * * *"

# Monthly on the 1st at 3 AM
BACKUP_SCHEDULE="0 3 1 * *"

# Every Monday at 3 AM
BACKUP_SCHEDULE="0 3 * * 1"
```

**Format:** `minute hour day-of-month month day-of-week`
- Use `*` for "any value"
- Use `*/n` for "every n units"
- Use `1-5` for ranges
- Use `1,3,5` for lists

## 📁 Volume Mounting

Map your data directory to the container:

```yaml
volumes:
  - /path/to/your/data:/backup         # Your data to backup
  - /path/to/logs:/var/log             # Optional: persist logs
```

**Note:** The default mount point is now `/backup` (not `/mnt/backup`).

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

## 🏥 Comprehensive Health Monitoring

The container includes advanced health monitoring that **automatically detects backup/restore failures** and marks the container UNHEALTHY.

### How It Works

The healthcheck monitors multiple layers:

#### 1. **Status Markers** (Immediate Detection ~60s)
- Backup and restore scripts write status files on failure
- Healthcheck reads these markers immediately
- Container goes UNHEALTHY within one healthcheck cycle

#### 2. **Log Analysis** (Recent Failures)
- Scans `backup.log` and `restore.log` for error keywords
- Detects failures within last 24 hours
- Looks for: "error", "failed", "fatal", "cannot", "unable to"

#### 3. **Process Monitoring**
- Verifies scheduler process is running
- Checks required environment variables
- Validates scripts are executable

#### 4. **Success Tracking**
- Tracks last successful backup timestamp
- Warns if no successful backup in 48+ hours

#### 5. **Periodic B2 Checks** (Every Hour)
- Tests repository connectivity
- Validates snapshot access
- Performs integrity checks (1% sample)

### Failure Detection

**When Backup Fails:**
1. `backup.sh` detects failure → writes `/tmp/backup_status`
2. Next healthcheck (within 60s) → reads status marker
3. Container marked **UNHEALTHY**
4. Log shows: `UNHEALTHY: Backup failed Xh ago - Reason: <reason>`

**When Restore Fails:**
1. `restore.sh` detects failure → writes `/tmp/restore_status`
2. Next healthcheck (within 60s) → reads status marker
3. Container marked **UNHEALTHY**
4. Log shows: `UNHEALTHY: Restore failed Xh ago - Reason: <reason>`

### Health Check Configuration

```yaml
healthcheck:
  test: ["CMD", "/src/healthcheck.sh"]
  interval: 60s          # Run every 60 seconds
  timeout: 30s           # Max 30s to complete
  retries: 3             # Mark unhealthy after 3 failures
  start_period: 30s      # Grace period on startup
```

### What Gets Checked

| Check | Frequency | Action on Failure |
|-------|-----------|-------------------|
| **Scheduler process** | Every 60s | UNHEALTHY |
| **Status markers** | Every 60s | UNHEALTHY |
| **Log analysis** | Every 60s | UNHEALTHY |
| **Environment vars** | Every 60s | UNHEALTHY |
| **Scripts executable** | Every 60s | UNHEALTHY |
| **Directory exists** | Every 60s | UNHEALTHY |
| **Success tracking** | Every 60s | WARNING only |
| **Disk space** | Every 60s | WARNING only |
| **B2 connectivity** | Once per hour | UNHEALTHY |
| **Repo integrity** | Once per hour | WARNING only |

### Monitoring Commands

```bash
# Check current health status
docker inspect backup --format='{{.State.Health.Status}}'

# View recent healthcheck output
docker inspect backup --format='{{range .State.Health.Log}}{{.Output}}{{end}}' | tail -1

# See unhealthy containers
docker ps --filter "health=unhealthy"

# Run healthcheck manually
docker-compose exec backup /src/healthcheck.sh

# Check status markers
docker-compose exec backup cat /tmp/backup_status
docker-compose exec backup cat /tmp/last_backup_success

# View healthcheck history
docker inspect backup --format='{{json .State.Health}}' | jq
```

### Testing Healthcheck

```bash
# Simulate backup failure
docker-compose exec backup sh -c 'echo -e "FAILED\n$(date +%s)\nTest failure" > /tmp/backup_status'

# Wait 60 seconds, then check
docker inspect backup | grep Health -A 5
# Should show "Status": "unhealthy"

# Clear failure status
docker-compose exec backup rm /tmp/backup_status
# Container becomes healthy again after next check
```

### Automatic Recovery with Autoheal

Pair with autoheal to automatically restart unhealthy containers:

```yaml
autoheal:
  image: willfarrell/autoheal
  environment:
    - AUTOHEAL_CONTAINER_LABEL=all
  volumes:
    - /var/run/docker.sock:/var/run/docker.sock
  restart: unless-stopped
```

When the container goes UNHEALTHY, autoheal will restart it automatically.

### Status Files

The healthcheck monitors these status files:

```bash
/tmp/backup_status         # Written when backup fails
/tmp/last_backup_success   # Timestamp of last successful backup
/tmp/restore_status        # Written when restore fails
/tmp/last_restore_success  # Timestamp of last successful restore
```

**Status File Format:**
```
FAILED                           # Line 1: Status
1728412800                       # Line 2: Unix timestamp
Restic backup command failed     # Line 3: Failure reason
```

### Healthcheck Output Examples

**Healthy:**
```
2025-10-08 15:30:00 - Performing basic healthcheck...
2025-10-08 15:30:00 - HEALTHY: Basic check passed (next full B2 check in 3540s)
```

**Unhealthy - Backup Failed:**
```
2025-10-08 15:30:00 - Performing basic healthcheck...
2025-10-08 15:30:00 - UNHEALTHY: Backup failed 2h ago - Reason: Restic backup command failed
```

**Unhealthy - Scheduler Dead:**
```
2025-10-08 15:30:00 - Performing basic healthcheck...
2025-10-08 15:30:00 - UNHEALTHY: scheduler is not running
```

### Recovery Steps

**Clear Failure Status:**
```bash
# Clear backup failure
docker-compose exec backup rm /tmp/backup_status

# Clear restore failure
docker-compose exec backup rm /tmp/restore_status

# Wait for next healthcheck (60s) - container should become healthy
```

**Force Immediate Healthcheck:**
```bash
docker-compose exec backup /src/healthcheck.sh
echo $?  # 0 = healthy, 1 = unhealthy
```

**Restart Container:**
```bash
docker-compose restart backup
# Check health after start_period (30s)
```

### Debugging Unhealthy Status

```bash
# Check why container is unhealthy
docker inspect backup --format='{{range .State.Health.Log}}{{.Output}}{{end}}' | tail -1

# Check all logs
docker-compose exec backup tail -50 /var/log/backup.log
docker-compose exec backup tail -50 /var/log/restore.log
docker-compose exec backup tail -50 /var/log/scheduler.log

# Check if scheduler is running
docker-compose exec backup ps aux | grep scheduler

# Test B2 connectivity manually
docker-compose exec backup restic list locks
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
docker-compose logs backup

# Run manual health check
docker-compose exec backup /src/healthcheck.sh

# Check status markers
docker-compose exec backup cat /tmp/backup_status
```

**Scheduler not running:**
```bash
# Verify scheduler is running
docker-compose exec backup ps aux | grep scheduler

# Check scheduler logs
docker-compose exec backup cat /var/log/scheduler.log

# Restart container
docker-compose restart backup
```

**Backups not running on schedule:**
```bash
# Check current time in container
docker-compose exec backup date

# Verify schedule format
docker-compose exec backup env | grep SCHEDULE

# Watch scheduler log
docker-compose exec backup tail -f /var/log/scheduler.log

# Test with 1-minute schedule temporarily
# Edit .env: BACKUP_SCHEDULE=*/1 * * * *
# Then rebuild: docker-compose up -d --force-recreate
```

### Debug Mode
```bash
# Run with debug output
docker-compose logs -f

# Check all log files
docker-compose exec backup cat /var/log/scheduler.log
docker-compose exec backup cat /var/log/backup.log
docker-compose exec backup cat /var/log/restore.log

# Interactive shell
docker-compose exec backup /bin/bash

# Test backup manually
docker-compose exec backup /src/backup.sh

# Test restore manually
docker-compose exec backup /src/restore.sh
```

## 💡 Best Practices

1. **Test Your Backup**: Run a test restore regularly to verify backups work
2. **Monitor Health**: Use healthcheck status and set up alerts for UNHEALTHY state
3. **Security**: Use application keys with minimal required B2 permissions
4. **Retention**: Adjust retention policies based on recovery needs and storage budget
5. **Startup Behavior**: Remember the container runs backup immediately on start
6. **Log Review**: Check `/var/log/scheduler.log` periodically for any warnings
7. **Disk Space**: Monitor backup source directory disk usage (alerts at 85%+)
8. **B2 Costs**: Full healthchecks run hourly to minimize B2 API calls
9. **Autoheal**: Pair with autoheal for automatic recovery from failures
10. **Updates**: Keep the container image updated for security patches

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
