#!/bin/bash

# Healthcheck script for backup container
# This script verifies that the container is healthy and backups are working correctly

# Set up environment variables
BACKUP_SOURCE_DIR="${BACKUP_SOURCE_DIR:-/backup}"
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY}"
export RESTIC_PASSWORD="${RESTIC_PASSWORD}"
export B2_ACCOUNT_ID="${B2_ACCOUNT_ID}"
export B2_ACCOUNT_KEY="${B2_ACCOUNT_KEY}"

# Healthcheck configuration
FULL_CHECK_INTERVAL="${HEALTHCHECK_FULL_INTERVAL:-3600}"  # Full B2 check every hour by default
LAST_FULL_CHECK_FILE="/tmp/last_full_healthcheck"

# Function to log with timestamp
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Determine if we should do a full check (including B2 calls)
DO_FULL_CHECK=false
if [ ! -f "$LAST_FULL_CHECK_FILE" ]; then
    DO_FULL_CHECK=true
else
    LAST_CHECK=$(cat "$LAST_FULL_CHECK_FILE" 2>/dev/null || echo "0")
    CURRENT_TIME=$(date +%s)
    TIME_SINCE_LAST=$((CURRENT_TIME - LAST_CHECK))
    
    if [ "$TIME_SINCE_LAST" -gt "$FULL_CHECK_INTERVAL" ]; then
        DO_FULL_CHECK=true
    fi
fi

# Always do basic checks (no B2 calls)
log "Performing basic healthcheck..."

# Check if scheduler process is running
if ! pgrep -f "scheduler.sh" > /dev/null; then
    log "UNHEALTHY: scheduler is not running"
    exit 1
fi

# Check if required environment variables are set
if [ -z "$RESTIC_REPOSITORY" ] || [ -z "$RESTIC_PASSWORD" ] || [ -z "$B2_ACCOUNT_ID" ] || [ -z "$B2_ACCOUNT_KEY" ]; then
    log "UNHEALTHY: Required environment variables are not set"
    exit 1
fi

# Check if backup scripts exist and are executable
if [ ! -x "/src/backup.sh" ] || [ ! -x "/src/restore.sh" ]; then
    log "UNHEALTHY: Backup scripts are missing or not executable"
    exit 1
fi

# Check if the backup source directory is mounted
if [ ! -d "$BACKUP_SOURCE_DIR" ]; then
    log "UNHEALTHY: Backup source directory $BACKUP_SOURCE_DIR is not mounted"
    exit 1
fi

# Check if scheduler log exists (indicates scheduler has started)
if [ ! -f "/var/log/scheduler.log" ]; then
    log "WARNING: Scheduler log not found yet"
fi

# Check for backup/restore status markers (written by backup.sh and restore.sh)
if [ -f "/tmp/backup_status" ]; then
    # Read status file
    STATUS=$(head -1 /tmp/backup_status 2>/dev/null)
    if [ "$STATUS" = "FAILED" ]; then
        TIMESTAMP=$(sed -n '2p' /tmp/backup_status 2>/dev/null || echo "0")
        REASON=$(sed -n '3p' /tmp/backup_status 2>/dev/null || echo "Unknown")
        CURRENT_TIME=$(date +%s)
        HOURS_AGO=$(( (CURRENT_TIME - TIMESTAMP) / 3600 ))
        
        if [ "$HOURS_AGO" -lt 24 ]; then
            log "UNHEALTHY: Backup failed ${HOURS_AGO}h ago - Reason: $REASON"
            exit 1
        else
            log "WARNING: Old backup failure detected (${HOURS_AGO}h ago)"
        fi
    fi
fi

if [ -f "/tmp/restore_status" ]; then
    # Read status file
    STATUS=$(head -1 /tmp/restore_status 2>/dev/null)
    if [ "$STATUS" = "FAILED" ]; then
        TIMESTAMP=$(sed -n '2p' /tmp/restore_status 2>/dev/null || echo "0")
        REASON=$(sed -n '3p' /tmp/restore_status 2>/dev/null || echo "Unknown")
        CURRENT_TIME=$(date +%s)
        HOURS_AGO=$(( (CURRENT_TIME - TIMESTAMP) / 3600 ))
        
        if [ "$HOURS_AGO" -lt 24 ]; then
            log "UNHEALTHY: Restore failed ${HOURS_AGO}h ago - Reason: $REASON"
            exit 1
        else
            log "WARNING: Old restore failure detected (${HOURS_AGO}h ago)"
        fi
    fi
fi

# Check for recent backup/restore failures in logs
FAILURE_CHECK_HOURS=24  # Check for failures in last 24 hours

# Check backup.log for failures
if [ -f "/var/log/backup.log" ]; then
    # Look for failure indicators in the last 100 lines
    if tail -100 /var/log/backup.log 2>/dev/null | grep -qi "error\|failed\|fatal\|cannot\|unable to"; then
        # Get the timestamp of the last error
        LAST_ERROR=$(tail -100 /var/log/backup.log | grep -i "error\|failed\|fatal" | tail -1)
        log "WARNING: Recent backup errors detected: $LAST_ERROR"
        
        # Check if this is recent (within last 24 hours)
        BACKUP_LOG_MTIME=$(stat -c %Y /var/log/backup.log 2>/dev/null || echo "0")
        CURRENT_TIME=$(date +%s)
        HOURS_SINCE_BACKUP_LOG=$(( (CURRENT_TIME - BACKUP_LOG_MTIME) / 3600 ))
        
        if [ "$HOURS_SINCE_BACKUP_LOG" -lt "$FAILURE_CHECK_HOURS" ]; then
            log "UNHEALTHY: Recent backup failure detected (within last ${FAILURE_CHECK_HOURS}h)"
            exit 1
        fi
    fi
fi

# Check restore.log for failures
if [ -f "/var/log/restore.log" ]; then
    # Look for failure indicators
    if tail -100 /var/log/restore.log 2>/dev/null | grep -qi "error\|failed\|fatal\|cannot\|unable to"; then
        LAST_ERROR=$(tail -100 /var/log/restore.log | grep -i "error\|failed\|fatal" | tail -1)
        log "WARNING: Recent restore errors detected: $LAST_ERROR"
        
        # Check if this is recent
        RESTORE_LOG_MTIME=$(stat -c %Y /var/log/restore.log 2>/dev/null || echo "0")
        CURRENT_TIME=$(date +%s)
        HOURS_SINCE_RESTORE_LOG=$(( (CURRENT_TIME - RESTORE_LOG_MTIME) / 3600 ))
        
        if [ "$HOURS_SINCE_RESTORE_LOG" -lt "$FAILURE_CHECK_HOURS" ]; then
            log "UNHEALTHY: Recent restore failure detected (within last ${FAILURE_CHECK_HOURS}h)"
            exit 1
        fi
    fi
fi

# Check scheduler.log for repeated failures
if [ -f "/var/log/scheduler.log" ]; then
    # Count recent failures (last 50 lines)
    RECENT_FAILURES=$(tail -50 /var/log/scheduler.log 2>/dev/null | grep -c "❌.*failed" || echo "0")
    
    if [ "$RECENT_FAILURES" -gt 3 ]; then
        log "UNHEALTHY: Multiple recent failures detected in scheduler ($RECENT_FAILURES failures)"
        exit 1
    fi
fi

# Check for successful backups
if [ -f "/tmp/last_backup_success" ]; then
    LAST_SUCCESS=$(cat /tmp/last_backup_success 2>/dev/null || echo "0")
    CURRENT_TIME=$(date +%s)
    HOURS_SINCE_SUCCESS=$(( (CURRENT_TIME - LAST_SUCCESS) / 3600 ))
    
    if [ "$HOURS_SINCE_SUCCESS" -gt 48 ]; then
        log "WARNING: Last successful backup was ${HOURS_SINCE_SUCCESS}h ago"
    fi
fi

# Check disk space in backup source directory
DISK_USAGE=$(df "$BACKUP_SOURCE_DIR" | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 95 ]; then
    log "WARNING: Backup source directory is $DISK_USAGE% full"
elif [ "$DISK_USAGE" -gt 85 ]; then
    log "INFO: Backup source directory is $DISK_USAGE% full"
fi

# Check if backup logs exist and are recent (local check, no B2 calls)
if [ -f "/var/log/backup.log" ]; then
    LOG_AGE=$(find /var/log/backup.log -mtime +2 2>/dev/null | wc -l)
    if [ "$LOG_AGE" -gt 0 ]; then
        log "WARNING: Backup log is older than 2 days"
    fi
fi

# Only do full B2 connectivity check if enough time has passed
if [ "$DO_FULL_CHECK" = "true" ]; then
    log "Performing full healthcheck with B2 connectivity test (interval: ${FULL_CHECK_INTERVAL}s)..."
    
    # Test restic repository connectivity (this calls B2)
    if ! timeout 20 restic list locks > /dev/null 2>&1; then
        # If repository doesn't exist or can't be accessed, try to initialize it
        log "Repository not accessible, attempting to initialize..."
        if ! timeout 20 restic init > /dev/null 2>&1; then
            log "UNHEALTHY: Cannot initialize or access restic repository"
            exit 1
        fi
        log "Repository initialized successfully"
    fi
    
    # Check if repository is functional by listing snapshots
    if timeout 20 restic snapshots --json > /tmp/snapshots.json 2>&1; then
        # Parse snapshot information
        SNAPSHOT_COUNT=$(cat /tmp/snapshots.json | grep -o '"time"' | wc -l)
        log "Found $SNAPSHOT_COUNT snapshots in repository"
        
        # Check for recent backups (within last 48 hours)
        if [ "$SNAPSHOT_COUNT" -gt 0 ]; then
            LATEST_SNAPSHOT=$(restic snapshots --json | grep '"time"' | tail -1 | cut -d'"' -f4)
            if [ -n "$LATEST_SNAPSHOT" ]; then
                # Convert snapshot time to epoch
                if command -v date > /dev/null; then
                    SNAPSHOT_EPOCH=$(date -d "$LATEST_SNAPSHOT" +%s 2>/dev/null || echo "0")
                    CURRENT_EPOCH=$(date +%s)
                    HOURS_SINCE_BACKUP=$(( (CURRENT_EPOCH - SNAPSHOT_EPOCH) / 3600 ))
                    
                    if [ "$HOURS_SINCE_BACKUP" -gt 48 ]; then
                        log "WARNING: Last backup is $HOURS_SINCE_BACKUP hours old (last: $LATEST_SNAPSHOT)"
                    else
                        log "Recent backup found: $LATEST_SNAPSHOT ($HOURS_SINCE_BACKUP hours ago)"
                    fi
                fi
            fi
        fi
        
        # Perform quick repository integrity check (1% sample, B2 call)
        log "Performing quick repository integrity check..."
        if ! timeout 30 restic check --read-data-subset=1% > /dev/null 2>&1; then
            log "WARNING: Repository integrity check failed (1% sample)"
        fi
    else
        log "WARNING: Cannot list snapshots from repository"
    fi
    
    # Update the last full check timestamp
    date +%s > "$LAST_FULL_CHECK_FILE"
    
    # Clean up temporary files
    rm -f /tmp/snapshots.json
    
    log "HEALTHY: Full check completed - backup system is operational"
else
    log "HEALTHY: Basic check passed (next full B2 check in $((FULL_CHECK_INTERVAL - TIME_SINCE_LAST))s)"
fi

exit 0