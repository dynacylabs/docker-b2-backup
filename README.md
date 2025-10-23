# Docker B2 Backup Container

A lightweight, automated backup solution using Docker, Restic, and Backblaze B2. This container automatically backs up your data to Backblaze B2 cloud storage with intelligent scheduling, automatic restore capabilities, and comprehensive health monitoring.

## ✨ Features

- **🚀 Configurable Startup Backup**: Optional backup on container start (default: enabled)
- **🔄 Auto-Restore**: Automatically detects empty directories and restores from latest snapshot
- **⏰ Simple Scheduler**: Cron-like syntax without the complexity (no cron daemon!)
- **☁️ Backblaze B2 Integration**: Secure, cost-effective cloud storage
- **🔐 Encryption**: End-to-end encryption via Restic
- **📦 Incremental Backups**: Efficient deduplication and compression
- **♻️ Smart Retention Management**: Automatic cleanup across all container restarts
- **🏥 Comprehensive Health Monitoring**: Automatic failure detection with detailed diagnostics
- **👤 User Management**: Configurable user permissions to match host system
- **🐳 Lightweight**: Alpine Linux base (~50MB image)
- **⚙️ Environment-Driven**: Fully configurable via environment variables
- **🔧 Intelligent Error Diagnosis**: Detailed error messages with specific troubleshooting steps

## 🏗️ Project Structure

```
docker-b2-backup/
├── src/
│   ├── backup.sh              # Main backup script with cross-host retention
│   ├── restore.sh             # Intelligent restore script (no nested directories)
│   ├── scheduler.sh           # Simple scheduler (replaces cron)
│   ├── entrypoint.sh          # Container initialization
│   ├── healthcheck.sh         # Comprehensive health monitoring
│   └── fix_nested_backup.sh  # Migration tool for old backup formats
├── Dockerfile                 # Alpine-based container definition
├── docker-compose.yml         # Example compose configuration
├── example.env                # Complete configuration template
└── README.md                  # This file
```

## 🔧 How It Works

This container uses a **simple scheduler script** instead of cron for maximum reliability and visibility.

### Backup Strategy

**Important:** The container backs up the **contents** of the mounted directory, not the directory itself. This ensures that when you restore:
- If you have `/backup/a`, `/backup/b`, `/backup/c`
- They restore as `/backup/a`, `/backup/b`, `/backup/c`
- **Not** as `/backup/backup/a`, `/backup/backup/b`, `/backup/backup/c`

### Startup Behavior

1. **On Container Start:**
   - Checks if backup directory is empty → restores latest snapshot if needed
   - Optionally runs initial backup (controlled by `RUN_BACKUP_ON_STARTUP`)
   - Starts scheduler loop

2. **During Operation:**
   - Checks every 60 seconds if current time matches schedule
   - Runs backup if schedule matches
   - Runs restore check if schedule matches (only if directory is empty)
   - Applies retention policy after each successful backup

3. **Retention Management:**
   - Automatically cleans up old snapshots after each backup
   - Groups snapshots by **paths** (not hostname) for consistent cleanup across container restarts
   - Respects configured retention policy (daily, weekly, monthly, yearly)

4. **Health Monitoring:**
   - Detects backup/restore failures within 60 seconds
   - Marks container UNHEALTHY automatically
   - Enables automatic restart with autoheal

### Why No Cron?

- ✅ **Simpler** - No crontab configuration
- ✅ **More reliable** - No permission issues
- ✅ **Better visibility** - All logs in stdout
- ✅ **Easier debugging** - See exactly what's happening
- ✅ **Same flexibility** - Supports cron syntax

## 🚀 Quick Start

### 1. Prepare Your Environment

```bash
# Create a directory for your data to backup
mkdir -p /path/to/your/data

# Clone the repository (optional - can build directly from GitHub)
git clone https://github.com/dynacylabs/docker-b2-backup.git
cd docker-b2-backup
```

### 2. Create Configuration File

Create a `.env` file or `b2-backup.env` with your settings:

```bash
# Required: Backblaze B2 Configuration
RESTIC_REPOSITORY=b2:your-bucket-name:backup-path
RESTIC_PASSWORD=your-secure-restic-password
B2_ACCOUNT_ID=your-b2-account-id
B2_ACCOUNT_KEY=your-b2-application-key

# Required: Backup Source
BACKUP_SOURCE_DIR=/backup

# Optional: Customize schedules (cron format)
BACKUP_SCHEDULE=0 0 * * *              # Daily at midnight
RESTORE_CHECK_SCHEDULE=0 0 * * *       # Daily at midnight
RUN_BACKUP_ON_STARTUP=false            # Don't backup on container start

# Optional: Retention Policy
RESTIC_KEEP_DAILY=7
RESTIC_KEEP_WEEKLY=4
RESTIC_KEEP_MONTHLY=6
RESTIC_KEEP_YEARLY=2
```

### 3. Create Docker Compose File

```yaml
services:
  b2-backup:
    build:
      context: https://github.com/dynacylabs/docker-b2-backup.git
      dockerfile: Dockerfile
    container_name: b2-backup
    volumes:
      - /path/to/your/data:/backup
    env_file:
      - ./b2-backup.env
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "/src/healthcheck.sh"]
      interval: 60s
      timeout: 60s
      retries: 3
      start_period: 60s
```

### 4. Deploy

```bash
docker compose up -d
```

### 5. Monitor

```bash
# Check container status and health
docker compose ps

# View logs in real-time
docker compose logs -f b2-backup

# View snapshots in repository
docker exec b2-backup restic snapshots

# Check last backup status
docker exec b2-backup cat /tmp/last_backup_success
```

## ⚙️ Configuration

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `RESTIC_REPOSITORY` | Backblaze B2 repository path | `b2:my-bucket:backups/server1` |
| `RESTIC_PASSWORD` | Encryption password for backups | `your-secure-password` |
| `B2_ACCOUNT_ID` | Backblaze B2 account ID | `005fb80d1ad8fa50000000002` |
| `B2_ACCOUNT_KEY` | Backblaze B2 application key | `K005xJm6AX6NmZgZHKWExjGq25XUftA` |

### Optional Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `BACKUP_SOURCE_DIR` | `/backup` | Directory to backup (contents, not directory itself) |
| `BACKUP_TEMP_DIR` | `/tmp/backup` | Temporary staging directory (legacy, not used in current version) |
| `BACKUP_SCHEDULE` | `0 2 * * *` | Schedule for backups (cron syntax) |
| `RESTORE_CHECK_SCHEDULE` | `0 1 * * *` | Schedule for restore checks (cron syntax) |
| `RUN_BACKUP_ON_STARTUP` | `true` | Run backup when container starts |
| `RESTIC_KEEP_DAILY` | `7` | Daily snapshots to retain |
| `RESTIC_KEEP_WEEKLY` | `4` | Weekly snapshots to retain |
| `RESTIC_KEEP_MONTHLY` | `6` | Monthly snapshots to retain |
| `RESTIC_KEEP_YEARLY` | `2` | Yearly snapshots to retain |
| `HEALTHCHECK_FULL_INTERVAL` | `3600` | Seconds between full B2 health checks |
| `PUID` | `1000` | User ID for file ownership (optional) |
| `PGID` | `1000` | Group ID for file ownership (optional) |

### Cron Schedule Examples

The scheduler uses familiar cron-like syntax:

```bash
# Format: minute hour day-of-month month day-of-week

# Daily at midnight
BACKUP_SCHEDULE="0 0 * * *"

# Daily at 2:30 AM
BACKUP_SCHEDULE="30 2 * * *"

# Every 6 hours
BACKUP_SCHEDULE="0 */6 * * *"

# Twice daily (midnight and noon)
BACKUP_SCHEDULE="0 0,12 * * *"

# Weekly on Sunday at 2 AM
BACKUP_SCHEDULE="0 2 * * 0"

# Monthly on the 1st at 3 AM
BACKUP_SCHEDULE="0 3 1 * *"

# Every 15 minutes (for testing)
BACKUP_SCHEDULE="*/15 * * * *"
```

**Format:** `minute hour day-of-month month day-of-week`
- Use `*` for "any value"
- Use `*/n` for "every n units"
- Use `1-5` for ranges
- Use `1,3,5` for lists
- Day of week: 0-7 (0 and 7 are Sunday)

## 📁 Volume Mounting

The container backs up the **contents** of your mounted directory, not the directory itself.

```yaml
services:
  b2-backup:
    volumes:
      - /path/to/your/data:/backup     # Your data to backup
```

**Important:**
- Mount your data directory to `/backup` (or configure `BACKUP_SOURCE_DIR`)
- The backup will store the contents directly (no nested `/backup/backup/` structure)
- On restore, files are placed directly in the mount point

**Example:**
If your host has `/home/user/mydata` containing `file1.txt` and `folder1/`:
```yaml
volumes:
  - /home/user/mydata:/backup
```

The backup will contain:
- `file1.txt`
- `folder1/`

On restore, they appear at:
- `/home/user/mydata/file1.txt`
- `/home/user/mydata/folder1/`

**Not** at `/home/user/mydata/backup/file1.txt` ✅

## 👤 User Permission Management

The container runs as the `backup` user (UID 1000, GID 1000 by default). Files in your backup directory should be readable by this user.

### Quick Setup (Most Common)

```bash
# Make your data readable by the backup user
sudo chown -R 1000:1000 /path/to/your/data

# Or make it world-readable (less secure)
sudo chmod -R 755 /path/to/your/data
```

### Custom User ID

If you need different permissions, set `PUID` and `PGID`:

```bash
# In your .env file
PUID=1003  # Your user ID (from: id -u)
PGID=1003  # Your group ID (from: id -g)
```

Then in your docker-compose.yml:

```yaml
services:
  b2-backup:
    user: "${PUID}:${PGID}"  # Or directly: user: "1003:1003"
```

## 🏥 Health Monitoring

The container includes comprehensive health monitoring that automatically detects failures and marks the container as UNHEALTHY.

### What Gets Monitored

| Check | Frequency | Action on Failure |
|-------|-----------|-------------------|
| Scheduler process running | Every 60s | UNHEALTHY |
| Backup status markers | Every 60s | UNHEALTHY |
| Restore status markers | Every 60s | UNHEALTHY |
| Recent log errors | Every 60s | UNHEALTHY |
| Environment variables | Every 60s | UNHEALTHY |
| Required scripts | Every 60s | UNHEALTHY |
| Last successful backup | Every 60s | WARNING (48h+) |
| Disk space | Every 60s | WARNING (85%+) |
| B2 connectivity | Every 1 hour | UNHEALTHY |
| Repository integrity | Every 1 hour | WARNING |

### Quick Health Check

```bash
# Check container health status
docker ps

# View detailed health output
docker inspect b2-backup --format='{{.State.Health.Status}}'

# Run manual health check
docker exec b2-backup /src/healthcheck.sh

# View last health check output
docker inspect b2-backup --format='{{range .State.Health.Log}}{{.Output}}{{end}}' | tail -1
```

### Understanding Health Status

**HEALTHY:**
```
2025-10-23 15:30:00 - HEALTHY: Basic check passed (next full B2 check in 3540s)
```

**UNHEALTHY:**
```
2025-10-23 15:30:00 - UNHEALTHY: Backup failed 2h ago - Reason: Network timeout
```

### Status Files

The container uses status files to track operations:

```bash
/tmp/backup_status           # Written on backup failure
/tmp/last_backup_success     # Timestamp of last successful backup
/tmp/restore_status          # Written on restore failure  
/tmp/last_restore_success    # Timestamp of last successful restore
```

### Auto-Recovery with Autoheal

Combine with [autoheal](https://github.com/willfarrell/docker-autoheal) to automatically restart unhealthy containers:

```yaml
services:
  autoheal:
    image: willfarrell/autoheal
    environment:
      - AUTOHEAL_CONTAINER_LABEL=all
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped

  b2-backup:
    # ... your backup config
    labels:
      autoheal: true  # Optional: explicit label
```

When the backup container goes UNHEALTHY, autoheal restarts it automatically.

## 🔄 Backup and Restore Operations

### Automatic Operations

The container handles most operations automatically:

- **Backup**: Runs on configured schedule (and optionally on startup)
- **Restore**: Automatically restores if backup directory is empty
- **Retention Cleanup**: Removes old snapshots after each backup
- **Health Checks**: Continuous monitoring every 60 seconds

### Manual Backup

```bash
# Run backup manually
docker exec b2-backup /src/backup.sh

# The script will:
# - Change to /backup directory
# - Backup current directory contents (.)
# - Apply retention policy (cleanup old snapshots)
# - Group snapshots by paths (not hostname)
```

### Manual Restore

```bash
# Restore latest snapshot
docker exec b2-backup /src/restore.sh

# Or restore specific snapshot
docker exec b2-backup restic restore <snapshot-id> --target /backup
```

### Snapshot Management

```bash
# List all snapshots
docker exec b2-backup restic snapshots

# View snapshot details
docker exec b2-backup restic snapshots --compact

# Repository statistics
docker exec b2-backup restic stats

# Check repository integrity
docker exec b2-backup restic check

# Check 10% of repository data
docker exec b2-backup restic check --read-data-subset=10%
```

### Manual Cleanup

```bash
# Clean up snapshots (already runs automatically after backup)
docker exec b2-backup restic forget \
  --group-by paths \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6 \
  --keep-yearly 2 \
  --prune

# Dry run (see what would be deleted)
docker exec b2-backup restic forget \
  --group-by paths \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6 \
  --keep-yearly 2 \
  --dry-run
```

### Migration from Old Backup Format

If you're upgrading from a version that created nested `/backup/backup/` directories:

```bash
# Run the fix script
docker exec b2-backup /src/fix_nested_backup.sh

# This will:
# - Detect nested backup directory
# - Move contents up one level
# - Run a fresh backup with correct structure
```

## 📊 Retention Policy

The retention policy controls how many snapshots are kept. Old snapshots are automatically deleted after each successful backup.

### Default Policy

- **7 daily** snapshots (last week)
- **4 weekly** snapshots (last ~month)
- **6 monthly** snapshots (last 6 months)  
- **2 yearly** snapshots (last 2 years)

**Approximate total**: ~19 snapshots maximum

### How Retention Works

1. **After each backup**, the cleanup process runs automatically
2. Snapshots are **grouped by paths** (not by hostname)
3. This means retention works correctly even if you:
   - Restart the container multiple times
   - Change the container hostname
   - Rebuild with a new container ID

**Example:** If you restart your container 10 times in one day, you'll still only keep 7 daily snapshots total (not 70).

### Customizing Retention

Adjust the values in your env file:

```bash
# Keep more history
RESTIC_KEEP_DAILY=14       # 2 weeks of daily backups
RESTIC_KEEP_WEEKLY=8       # 2 months of weekly backups
RESTIC_KEEP_MONTHLY=12     # 1 year of monthly backups
RESTIC_KEEP_YEARLY=5       # 5 years of yearly backups

# Keep less (save storage costs)
RESTIC_KEEP_DAILY=3        # Only 3 days
RESTIC_KEEP_WEEKLY=2       # Only 2 weeks
RESTIC_KEEP_MONTHLY=3      # Only 3 months
RESTIC_KEEP_YEARLY=1       # Only 1 year
```

### Important Notes

- Retention is enforced **after every successful backup**
- Uses `--group-by paths` to avoid per-hostname retention groups
- Snapshots are permanently deleted with `--prune` flag
- Failed cleanup doesn't fail the backup (warning only)

## 🔧 Troubleshooting

### Common Issues

#### Multiple Snapshots on Same Day

**Symptom:** You see multiple snapshots with the same date in `restic snapshots`

**Cause:** The container runs a backup on startup by default (`RUN_BACKUP_ON_STARTUP=true`)

**Solution:** 
```bash
# Disable startup backup
echo "RUN_BACKUP_ON_STARTUP=false" >> b2-backup.env

# Rebuild container
docker compose up -d --force-recreate b2-backup
```

The retention policy will clean up excess snapshots on the next scheduled backup.

---

#### Too Many Snapshots (Retention Not Working)

**Symptom:** You have dozens of snapshots instead of ~19

**Cause:** Old version didn't use `--group-by paths`, so each container restart created a new retention group

**Solution:**
```bash
# Manual cleanup with correct grouping
docker exec b2-backup restic forget \
  --group-by paths \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 6 \
  --keep-yearly 2 \
  --prune

# Update container to latest version
docker compose pull b2-backup  # Or rebuild from GitHub
docker compose up -d b2-backup
```

---

#### Nested Backup Directory (old issue)

**Symptom:** Files restore to `/backup/backup/` instead of `/backup/`

**Cause:** Using old backup format that backed up the directory instead of its contents

**Solution:**
```bash
# Run the migration script
docker exec b2-backup /src/fix_nested_backup.sh

# Or manually:
docker exec b2-backup bash -c "mv /backup/backup/* /backup/ && rmdir /backup/backup"
docker exec b2-backup /src/backup.sh  # Create new backup with correct structure
```

---

#### Permission Denied Errors

**Symptom:** Backup fails with "permission denied" errors

**Solution:**
```bash
# Option 1: Fix ownership
sudo chown -R 1000:1000 /path/to/your/data

# Option 2: Make readable
sudo chmod -R 755 /path/to/your/data

# Option 3: Use your own UID/GID
# In docker-compose.yml:
user: "$(id -u):$(id -g)"
```

---

#### B2 Authentication Errors

**Symptom:** Errors about authentication, 401, or 403

**Solution:**
```bash
# Verify credentials in env file
docker exec b2-backup env | grep B2_

# Check B2 account:
# 1. Login to Backblaze B2 console
# 2. Verify application key hasn't expired
# 3. Check key has proper permissions (read/write)
# 4. Verify bucket exists

# Test B2 connectivity
docker exec b2-backup restic snapshots
```

---

#### Container Marked UNHEALTHY

**Symptom:** `docker ps` shows container as "unhealthy"

**Solution:**
```bash
# Check why unhealthy
docker inspect b2-backup --format='{{range .State.Health.Log}}{{.Output}}{{end}}' | tail -1

# View detailed status
docker exec b2-backup /src/healthcheck.sh

# Check for failure markers
docker exec b2-backup cat /tmp/backup_status
docker exec b2-backup cat /tmp/restore_status

# Clear failure status and let it retry
docker exec b2-backup rm -f /tmp/backup_status /tmp/restore_status

# Or restart container
docker compose restart b2-backup
```

---

#### Scheduler Not Running Backups

**Symptom:** No backups at scheduled time

**Solution:**
```bash
# Check scheduler is running
docker exec b2-backup ps aux | grep scheduler

# Verify schedule format
docker exec b2-backup env | grep SCHEDULE

# Check container time
docker exec b2-backup date

# Test with frequent schedule (every 2 minutes)
# In b2-backup.env:
BACKUP_SCHEDULE=*/2 * * * *

# Watch logs
docker logs -f b2-backup
```

---

### Debug Commands

```bash
# View all logs
docker logs b2-backup --tail 100

# Interactive shell
docker exec -it b2-backup /bin/bash

# Test backup manually
docker exec b2-backup /src/backup.sh

# Test restore manually  
docker exec b2-backup /src/restore.sh

# Check environment variables
docker exec b2-backup env

# List snapshots
docker exec b2-backup restic snapshots

# Repository info
docker exec b2-backup restic stats

# Health status
docker exec b2-backup /src/healthcheck.sh
echo $?  # 0 = healthy, 1 = unhealthy
```

### Getting Help

If you encounter issues:

1. Check this troubleshooting section
2. Enable debug logging: `docker logs -f b2-backup`
3. Run manual health check: `docker exec b2-backup /src/healthcheck.sh`
4. Check [GitHub Issues](https://github.com/dynacylabs/docker-b2-backup/issues)
5. Open a new issue with:
   - Container logs
   - Health check output
   - Your docker-compose.yml (redact credentials)
   - Steps to reproduce

## 💡 Best Practices

1. **Test Your Backups Regularly**
   ```bash
   # Restore to a test directory periodically
   docker exec b2-backup restic restore latest --target /tmp/restore-test
   ```

2. **Monitor Health Status**
   ```bash
   # Set up monitoring alerts for unhealthy containers
   docker ps --filter "health=unhealthy"
   ```

3. **Secure Your Credentials**
   - Use application keys with minimal B2 permissions (read/write to specific bucket)
   - Store `.env` files securely (never commit to git)
   - Rotate B2 keys periodically

4. **Optimize Retention Policy**
   - Balance recovery needs vs. storage costs
   - Daily backups are for recent recovery (7 days)
   - Weekly/monthly for longer-term recovery
   - Yearly for compliance/archival

5. **Configure Startup Backup**
   - Set `RUN_BACKUP_ON_STARTUP=false` for production (avoids duplicate backups)
   - Keep `true` for testing or critical systems

6. **Schedule Wisely**
   - Run backups during low-activity periods
   - Avoid overlapping backup and restore schedules
   - Common: `BACKUP_SCHEDULE=0 0 * * *` (midnight daily)

7. **Monitor Disk Space**
   - The healthcheck warns at 85% disk usage
   - Monitor backup source directory size
   - Prune old files before they're backed up

8. **Understand Retention Grouping**
   - Retention is by **paths**, not hostname
   - Container restarts don't create separate retention groups
   - All snapshots are treated as one logical backup set

9. **Use Autoheal for Recovery**
   ```yaml
   # Add to docker-compose.yml
   autoheal:
     image: willfarrell/autoheal
     volumes:
       - /var/run/docker.sock:/var/run/docker.sock
     restart: unless-stopped
   ```

10. **Keep Container Updated**
    ```bash
    # Pull latest changes
    docker compose pull b2-backup
    # Or rebuild from GitHub
    docker compose up -d --build b2-backup
    ```

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## 📝 Changelog

### Recent Improvements

- ✅ **Fixed nested backup directory issue** - Now backs up directory contents, not the directory itself
- ✅ **Fixed retention policy** - Uses `--group-by paths` to cleanup across all container restarts
- ✅ **Added configurable startup backup** - `RUN_BACKUP_ON_STARTUP` environment variable
- ✅ **Improved error diagnostics** - Detailed error messages with specific troubleshooting
- ✅ **Added migration tool** - `fix_nested_backup.sh` for upgrading from old format

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- [Restic](https://restic.net/) - Fast, secure, efficient backup program
- [Backblaze B2](https://www.backblaze.com/b2/) - Affordable, reliable cloud storage
- [Alpine Linux](https://alpinelinux.org/) - Lightweight, secure container base

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/dynacylabs/docker-b2-backup/issues)
- **Discussions**: [GitHub Discussions](https://github.com/dynacylabs/docker-b2-backup/discussions)
- **Documentation**: This README and inline code comments

---

**Made with ❤️ by [Dynacylabs](https://github.com/dynacylabs)**
