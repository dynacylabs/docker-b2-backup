#!/bin/bash

# Simple entrypoint that runs the scheduler
# No cron needed - just a simple loop-based scheduler

# Handle user/group ID mapping for file permissions
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# Check if we need to update user/group IDs
if [ "$PUID" != "1000" ] || [ "$PGID" != "1000" ]; then
    echo "Updating user/group IDs to PUID=$PUID, PGID=$PGID"
    
    if [ "$(id -u)" = "0" ]; then
        # Update group
        if [ "$PGID" != "1000" ]; then
            groupmod -g "$PGID" backup 2>/dev/null || groupadd -g "$PGID" backup
        fi
        
        # Update user
        if [ "$PUID" != "1000" ]; then
            usermod -u "$PUID" -g "$PGID" backup 2>/dev/null || useradd -u "$PUID" -g "$PGID" -s /bin/bash backup
        fi
        
        # Fix ownership of directories
        chown -R backup:backup /var/log /src 2>/dev/null || true
    else
        echo "Warning: Cannot change user/group IDs - not running as root"
    fi
fi

# Ensure backup source directory has correct permissions
BACKUP_SOURCE_DIR="${BACKUP_SOURCE_DIR:-/backup}"
if [ -d "$BACKUP_SOURCE_DIR" ]; then
    chown backup:backup "$BACKUP_SOURCE_DIR" 2>/dev/null || true
fi

# Create log directory with proper permissions
mkdir -p /var/log 2>/dev/null || true
touch /var/log/backup.log /var/log/restore.log /var/log/scheduler.log 2>/dev/null || true
if [ "$(id -u)" = "0" ]; then
    chown backup:backup /var/log /var/log/backup.log /var/log/restore.log /var/log/scheduler.log 2>/dev/null || true
    chmod 666 /var/log/backup.log /var/log/restore.log /var/log/scheduler.log 2>/dev/null || true
fi

echo "=========================================="
echo "🚀 Starting Backup Scheduler"
echo "=========================================="
echo "Backup source: ${BACKUP_SOURCE_DIR}"
echo "Backup schedule: ${BACKUP_SCHEDULE:-0 2 * * *}"
echo "Restore check schedule: ${RESTORE_CHECK_SCHEDULE:-0 1 * * *}"
echo "=========================================="

# Run scheduler as backup user if root, otherwise as current user
if [ "$(id -u)" = "0" ]; then
    echo "Running scheduler as backup user..."
    exec su backup -c "/src/scheduler.sh" 2>&1 | tee /var/log/scheduler.log
else
    echo "Running scheduler as current user..."
    exec /src/scheduler.sh 2>&1 | tee /var/log/scheduler.log
fi