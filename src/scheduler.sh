#!/bin/bash

# Scheduler script - runs backup and restore on a schedule without cron
# This script parses cron-like syntax and executes tasks at the appropriate times

set -e

# Load environment variables
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY}"
export RESTIC_PASSWORD="${RESTIC_PASSWORD}"
export B2_ACCOUNT_ID="${B2_ACCOUNT_ID}"
export B2_ACCOUNT_KEY="${B2_ACCOUNT_KEY}"
export BACKUP_SOURCE_DIR="${BACKUP_SOURCE_DIR:-/backup}"
export BACKUP_TEMP_DIR="${BACKUP_TEMP_DIR:-/tmp/backup}"
export RESTIC_KEEP_DAILY="${RESTIC_KEEP_DAILY:-7}"
export RESTIC_KEEP_WEEKLY="${RESTIC_KEEP_WEEKLY:-4}"
export RESTIC_KEEP_MONTHLY="${RESTIC_KEEP_MONTHLY:-6}"
export RESTIC_KEEP_YEARLY="${RESTIC_KEEP_YEARLY:-2}"

# Get schedules from environment (cron-like syntax)
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"
RESTORE_CHECK_SCHEDULE="${RESTORE_CHECK_SCHEDULE:-0 1 * * *}"

# Log with timestamp
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Parse cron expression and check if current time matches
# Format: minute hour day month weekday
check_cron_match() {
    local cron_expr="$1"
    local current_min=$(date +%M | sed 's/^0//')
    local current_hour=$(date +%H | sed 's/^0//')
    local current_day=$(date +%d | sed 's/^0//')
    local current_month=$(date +%m | sed 's/^0//')
    local current_weekday=$(date +%u)  # 1-7 (Monday-Sunday)
    
    # Handle Sunday as both 0 and 7
    if [ "$current_weekday" = "7" ]; then
        current_weekday="0"
    fi
    
    # Parse cron fields
    read -r min hour day month weekday <<< "$cron_expr"
    
    # Check each field
    # Minute
    if ! check_cron_field "$min" "$current_min" 0 59; then
        return 1
    fi
    
    # Hour
    if ! check_cron_field "$hour" "$current_hour" 0 23; then
        return 1
    fi
    
    # Day of month
    if ! check_cron_field "$day" "$current_day" 1 31; then
        return 1
    fi
    
    # Month
    if ! check_cron_field "$month" "$current_month" 1 12; then
        return 1
    fi
    
    # Day of week
    if ! check_cron_field "$weekday" "$current_weekday" 0 7; then
        return 1
    fi
    
    return 0
}

# Check if a cron field matches the current value
check_cron_field() {
    local field="$1"
    local current="$2"
    local min_val="$3"
    local max_val="$4"
    
    # Remove leading zeros for comparison
    current=$(echo "$current" | sed 's/^0*//')
    [ -z "$current" ] && current=0
    
    # * means any value
    if [ "$field" = "*" ]; then
        return 0
    fi
    
    # */n means every n units
    if [[ "$field" =~ ^\*/([0-9]+)$ ]]; then
        local step="${BASH_REMATCH[1]}"
        if [ $((current % step)) -eq 0 ]; then
            return 0
        else
            return 1
        fi
    fi
    
    # Check for ranges (e.g., 1-5)
    if [[ "$field" =~ ^([0-9]+)-([0-9]+)$ ]]; then
        local start="${BASH_REMATCH[1]}"
        local end="${BASH_REMATCH[2]}"
        if [ "$current" -ge "$start" ] && [ "$current" -le "$end" ]; then
            return 0
        else
            return 1
        fi
    fi
    
    # Check for lists (e.g., 1,3,5)
    if [[ "$field" =~ , ]]; then
        IFS=',' read -ra values <<< "$field"
        for val in "${values[@]}"; do
            val=$(echo "$val" | sed 's/^0*//')
            [ -z "$val" ] && val=0
            if [ "$val" -eq "$current" ]; then
                return 0
            fi
        done
        return 1
    fi
    
    # Direct value comparison
    field=$(echo "$field" | sed 's/^0*//')
    [ -z "$field" ] && field=0
    if [ "$field" -eq "$current" ]; then
        return 0
    fi
    
    return 1
}

# Run backup
run_backup() {
    log "🔄 Starting scheduled backup..."
    # Capture output to both log file and variable for error reporting
    BACKUP_OUTPUT=$(/src/backup.sh 2>&1 | tee -a /var/log/backup.log)
    BACKUP_EXIT_CODE=${PIPESTATUS[0]}
    
    if [ $BACKUP_EXIT_CODE -eq 0 ]; then
        log "✅ Backup completed successfully"
    else
        log "❌ Backup failed"
        # Display the error output directly to console
        echo "$BACKUP_OUTPUT" | grep -A 100 "^========================================$" || echo "$BACKUP_OUTPUT"
    fi
}

# Run restore check (only if directory is empty)
run_restore_check() {
    if [ -z "$(ls -A ${BACKUP_SOURCE_DIR} 2>/dev/null)" ]; then
        log "🔄 Directory is empty, starting restore..."
        # Capture output to both log file and variable for error reporting
        RESTORE_OUTPUT=$(/src/restore.sh 2>&1 | tee -a /var/log/restore.log)
        RESTORE_EXIT_CODE=${PIPESTATUS[0]}
        
        if [ $RESTORE_EXIT_CODE -eq 0 ]; then
            log "✅ Restore completed successfully"
        else
            log "❌ Restore failed"
            # Display the error output directly to console
            echo "$RESTORE_OUTPUT" | grep -A 100 "^========================================$" || echo "$RESTORE_OUTPUT"
        fi
    else
        log "ℹ️  Directory not empty, skipping restore check"
    fi
}

# Initial startup tasks
log "=========================================="
log "📦 Backup Scheduler Starting"
log "=========================================="
log "Backup schedule: $BACKUP_SCHEDULE"
log "Restore check schedule: $RESTORE_CHECK_SCHEDULE"
log "Backup source: $BACKUP_SOURCE_DIR"
log "=========================================="

# Check if directory is empty on startup and restore if needed
log "🔍 Checking if initial restore is needed..."
if [ -z "$(ls -A ${BACKUP_SOURCE_DIR} 2>/dev/null)" ]; then
    log "📂 Directory is empty, performing initial restore..."
    run_restore_check
else
    log "📂 Directory contains data, skipping initial restore"
fi

# Run backup on startup if enabled (default: true)
RUN_BACKUP_ON_STARTUP="${RUN_BACKUP_ON_STARTUP:-true}"
if [ "$RUN_BACKUP_ON_STARTUP" = "true" ]; then
    log "🚀 Running initial backup on startup..."
    run_backup
else
    log "⏭️  Skipping initial backup (RUN_BACKUP_ON_STARTUP=false)"
fi

# Track last execution times to avoid running multiple times in the same minute
last_backup_minute=""
last_restore_minute=""

log "=========================================="
log "⏰ Scheduler is now running..."
log "=========================================="

# Main loop - check every minute
while true; do
    # Get current minute marker
    current_minute=$(date +%Y%m%d%H%M)
    
    # Check backup schedule
    if [ "$last_backup_minute" != "$current_minute" ]; then
        if check_cron_match "$BACKUP_SCHEDULE"; then
            run_backup
            last_backup_minute="$current_minute"
        fi
    fi
    
    # Check restore schedule
    if [ "$last_restore_minute" != "$current_minute" ]; then
        if check_cron_match "$RESTORE_CHECK_SCHEDULE"; then
            run_restore_check
            last_restore_minute="$current_minute"
        fi
    fi
    
    # Sleep for 60 seconds
    sleep 60
done
