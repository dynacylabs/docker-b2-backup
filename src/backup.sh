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

    # Initialize the Restic repository if it doesn't exist
    restic init || true

    # Backup the mounted directory directly to Backblaze B2
    # Use --tag to identify the backup source
    BACKUP_ERROR=$(restic backup "$MOUNTED_DIR" --tag "$(hostname)" --tag "backup-$(date +%Y%m%d)" 2>&1)
    BACKUP_EXIT_CODE=$?
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
        echo "========================================" >&2
        echo "WARNING: Snapshot cleanup failed with exit code $CLEANUP_EXIT_CODE" >&2
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')" >&2
        echo "----------------------------------------" >&2
        echo "Error details:" >&2
        echo "$CLEANUP_ERROR" >&2
        echo "========================================" >&2
        # Don't fail on cleanup errors, backup succeeded
    fi

    echo "Backup completed successfully."
    mark_success
fi