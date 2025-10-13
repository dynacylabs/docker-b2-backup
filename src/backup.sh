#!/bin/bash

# Status tracking
STATUS_FILE="/tmp/backup_status"
LAST_SUCCESS_FILE="/tmp/last_backup_success"

# Function to mark failure
mark_failure() {
    echo "FAILED" > "$STATUS_FILE"
    echo "$(date +%s)" >> "$STATUS_FILE"
    echo "$1" >> "$STATUS_FILE"
}

# Function to mark success
mark_success() {
    echo "SUCCESS" > "$STATUS_FILE"
    echo "$(date +%s)" > "$LAST_SUCCESS_FILE"
    rm -f "$STATUS_FILE"  # Clear failure status
}

# Function to check if repository is locked
check_and_unlock() {
    echo "Checking for stale locks..."
    local LOCKS_OUTPUT=$(restic list locks 2>&1)
    local LOCKS_EXIT_CODE=$?
    
    if [ $LOCKS_EXIT_CODE -ne 0 ]; then
        echo "Warning: Unable to check locks (this is normal if repository doesn't exist yet)"
        return 0
    fi
    
    # Check if there are any locks
    if echo "$LOCKS_OUTPUT" | grep -q '^[a-f0-9]'; then
        echo "Found existing locks. Attempting to unlock stale locks..."
        local UNLOCK_OUTPUT=$(restic unlock 2>&1)
        local UNLOCK_EXIT_CODE=$?
        
        if [ $UNLOCK_EXIT_CODE -eq 0 ]; then
            echo "Successfully removed stale locks"
        else
            echo "Warning: Failed to unlock repository" >&2
            echo "$UNLOCK_OUTPUT" >&2
            return 1
        fi
    else
        echo "No stale locks found"
    fi
    return 0
}

# Function to handle lock errors and retry
handle_lock_error() {
    local error_output="$1"
    local command_name="$2"
    
    # Check if the error is lock-related
    if echo "$error_output" | grep -qi "unable to create lock\|repository is already locked\|lock.*failed"; then
        echo "========================================" >&2
        echo "Lock error detected in $command_name" >&2
        echo "Attempting to remove stale locks and retry..." >&2
        echo "========================================" >&2
        
        # Try to unlock
        restic unlock 2>&1
        return 0  # Indicate this was a lock error
    fi
    return 1  # Not a lock error
}

# Define variables from environment with defaults
MOUNTED_DIR="${BACKUP_SOURCE_DIR:-/backup}"
TEMP_DIR="${BACKUP_TEMP_DIR:-/tmp/backup}"
RESTIC_REPOSITORY="${RESTIC_REPOSITORY}"
RESTIC_PASSWORD="${RESTIC_PASSWORD}"

# Backblaze B2 credentials
export B2_ACCOUNT_ID="${B2_ACCOUNT_ID}"
export B2_ACCOUNT_KEY="${B2_ACCOUNT_KEY}"

# Validate required environment variables
if [ -z "$RESTIC_REPOSITORY" ]; then
    echo "Error: RESTIC_REPOSITORY environment variable is required"
    mark_failure "Missing RESTIC_REPOSITORY"
    exit 1
fi

if [ -z "$RESTIC_PASSWORD" ]; then
    echo "Error: RESTIC_PASSWORD environment variable is required"
    mark_failure "Missing RESTIC_PASSWORD"
    exit 1
fi

if [ -z "$B2_ACCOUNT_ID" ] || [ -z "$B2_ACCOUNT_KEY" ]; then
    echo "Error: B2_ACCOUNT_ID and B2_ACCOUNT_KEY environment variables are required"
    mark_failure "Missing B2 credentials"
    exit 1
fi

# Check if the mounted directory is empty
if [ -z "$(ls -A $MOUNTED_DIR)" ]; then
    echo "Mounted directory is empty. Restoring the latest backup from Backblaze B2..."
    /restore.sh
else
    echo "Starting backup process..."
    
    # Set the Restic environment variables
    export RESTIC_REPOSITORY
    export RESTIC_PASSWORD

    # Check for and remove stale locks before starting
    check_and_unlock

    # Initialize the Restic repository if it doesn't exist
    restic init || true

    # Backup the mounted directory directly to Backblaze B2
    # Use --tag to identify the backup source
    BACKUP_ERROR=$(restic backup "$MOUNTED_DIR" --tag "$(hostname)" --tag "backup-$(date +%Y%m%d)" 2>&1)
    BACKUP_EXIT_CODE=$?
    if [ $BACKUP_EXIT_CODE -ne 0 ]; then
        # Check if this is a lock error and retry once
        if handle_lock_error "$BACKUP_ERROR" "backup"; then
            echo "Retrying backup after lock removal..." >&2
            BACKUP_ERROR=$(restic backup "$MOUNTED_DIR" --tag "$(hostname)" --tag "backup-$(date +%Y%m%d)" 2>&1)
            BACKUP_EXIT_CODE=$?
        fi
        
        if [ $BACKUP_EXIT_CODE -ne 0 ]; then
            echo "========================================" >&2
            echo "ERROR: Backup failed with exit code $BACKUP_EXIT_CODE" >&2
            echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')" >&2
            echo "Source: $MOUNTED_DIR" >&2
            echo "Repository: $RESTIC_REPOSITORY" >&2
            echo "----------------------------------------" >&2
            echo "Error details:" >&2
            echo "$BACKUP_ERROR" >&2
            echo "========================================" >&2
            mark_failure "Restic backup command failed with exit code $BACKUP_EXIT_CODE"
            exit 1
        else
            echo "Backup succeeded after retry"
        fi
    fi

    # Clean up old snapshots based on retention policy
    KEEP_DAILY="${RESTIC_KEEP_DAILY:-7}"
    KEEP_WEEKLY="${RESTIC_KEEP_WEEKLY:-4}"
    KEEP_MONTHLY="${RESTIC_KEEP_MONTHLY:-6}"
    KEEP_YEARLY="${RESTIC_KEEP_YEARLY:-2}"

    echo "Cleaning up old snapshots (keeping: ${KEEP_DAILY} daily, ${KEEP_WEEKLY} weekly, ${KEEP_MONTHLY} monthly, ${KEEP_YEARLY} yearly)..."
    CLEANUP_ERROR=$(restic forget --keep-daily $KEEP_DAILY --keep-weekly $KEEP_WEEKLY --keep-monthly $KEEP_MONTHLY --keep-yearly $KEEP_YEARLY --prune 2>&1)
    CLEANUP_EXIT_CODE=$?
    if [ $CLEANUP_EXIT_CODE -ne 0 ]; then
        # Check if this is a lock error and retry once
        if handle_lock_error "$CLEANUP_ERROR" "cleanup"; then
            echo "Retrying cleanup after lock removal..." >&2
            CLEANUP_ERROR=$(restic forget --keep-daily $KEEP_DAILY --keep-weekly $KEEP_WEEKLY --keep-monthly $KEEP_MONTHLY --keep-yearly $KEEP_YEARLY --prune 2>&1)
            CLEANUP_EXIT_CODE=$?
        fi
        
        if [ $CLEANUP_EXIT_CODE -ne 0 ]; then
            echo "========================================" >&2
            echo "WARNING: Snapshot cleanup failed with exit code $CLEANUP_EXIT_CODE" >&2
            echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')" >&2
            echo "----------------------------------------" >&2
            echo "Error details:" >&2
            echo "$CLEANUP_ERROR" >&2
            echo "========================================" >&2
        else
            echo "Cleanup succeeded after retry"
        fi
        # Don't fail on cleanup errors, backup succeeded
    fi

    echo "Backup completed successfully."
    mark_success
fi