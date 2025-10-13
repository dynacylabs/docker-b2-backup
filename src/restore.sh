#!/bin/bash

# Status tracking
STATUS_FILE="/tmp/restore_status"
LAST_SUCCESS_FILE="/tmp/last_restore_success"

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
RESTORE_DIR="${BACKUP_SOURCE_DIR:-/backup}"
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

    # Set the Restic environment variables
    export RESTIC_REPOSITORY
    export RESTIC_PASSWORD

    # Check for and remove stale locks before starting
    check_and_unlock

    # Check if the restore directory is empty
if [ -z "$(ls -A $RESTORE_DIR)" ]; then
    echo "Restore directory is empty. Restoring the latest backup from Backblaze B2..."
    
    # Create a temporary restore directory
    TEMP_RESTORE="/tmp/restore_temp"
    mkdir -p "$TEMP_RESTORE"
    
    # Restore the latest backup to temporary directory
    RESTORE_ERROR=$(restic restore latest --target "$TEMP_RESTORE" 2>&1)
    RESTORE_EXIT_CODE=$?
    if [ $RESTORE_EXIT_CODE -ne 0 ]; then
        # Check if this is a lock error and retry once
        if handle_lock_error "$RESTORE_ERROR" "restore"; then
            echo "Retrying restore after lock removal..." >&2
            RESTORE_ERROR=$(restic restore latest --target "$TEMP_RESTORE" 2>&1)
            RESTORE_EXIT_CODE=$?
        fi
        
        if [ $RESTORE_EXIT_CODE -ne 0 ]; then
            echo "========================================" >&2
            echo "ERROR: Restore failed with exit code $RESTORE_EXIT_CODE" >&2
            echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')" >&2
            echo "Target: $TEMP_RESTORE" >&2
            echo "Repository: $RESTIC_REPOSITORY" >&2
            echo "----------------------------------------" >&2
            echo "Error details:" >&2
            echo "$RESTORE_ERROR" >&2
            echo "========================================" >&2
            mark_failure "Restic restore command failed with exit code $RESTORE_EXIT_CODE"
            rm -rf "$TEMP_RESTORE"
            exit 1
        else
            echo "Restore succeeded after retry"
        fi
    fi
    
    # Check if restore created nested structure (old backups) or direct structure (new backups)
    if [ -d "$TEMP_RESTORE/tmp/backup" ]; then
        echo "Detected old backup format with nested directories. Moving files to correct location..."
        # Move files from nested structure
        mv "$TEMP_RESTORE/tmp/backup/"* "$RESTORE_DIR/" 2>/dev/null || true
        mv "$TEMP_RESTORE/tmp/backup/".* "$RESTORE_DIR/" 2>/dev/null || true
    elif [ -d "$TEMP_RESTORE$(basename $RESTORE_DIR)" ]; then
        echo "Detected new backup format. Moving files to correct location..."
        # Move files from backup directory structure
        mv "$TEMP_RESTORE$(basename $RESTORE_DIR)/"* "$RESTORE_DIR/" 2>/dev/null || true
        mv "$TEMP_RESTORE$(basename $RESTORE_DIR)/".* "$RESTORE_DIR/" 2>/dev/null || true
    else
        echo "Direct restore structure detected. Moving files..."
        # Move everything from temp to restore directory
        find "$TEMP_RESTORE" -mindepth 1 -maxdepth 1 -exec mv {} "$RESTORE_DIR/" \; 2>/dev/null || true
    fi
    
    # Clean up temporary directory
    rm -rf "$TEMP_RESTORE"
    
    # Verify restore succeeded (directory should not be empty)
    if [ -z "$(ls -A $RESTORE_DIR)" ]; then
        echo "========================================" >&2
        echo "ERROR: Restore completed but directory is still empty" >&2
        echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')" >&2
        echo "Target directory: $RESTORE_DIR" >&2
        echo "Temp restore directory contents:" >&2
        ls -la "$TEMP_RESTORE" 2>&1 || echo "Temp directory already cleaned up" >&2
        echo "========================================" >&2
        mark_failure "Restore completed but no files were restored"
        exit 1
    fi
    
    echo "Restore completed successfully."
    mark_success
else
    echo "Restore directory is not empty. No restore action taken."
fi