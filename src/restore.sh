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

# Function to diagnose and report detailed errors
diagnose_error() {
    local error_output="$1"
    local operation="$2"
    local exit_code="$3"
    
    echo "========================================" >&2
    echo "ERROR: $operation failed with exit code $exit_code" >&2
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')" >&2
    echo "Repository: $RESTIC_REPOSITORY" >&2
    echo "----------------------------------------" >&2
    
    # Analyze error output for specific issues
    if echo "$error_output" | grep -qi "authentication\|401\|403\|invalid.*credentials\|access.*denied"; then
        echo "DIAGNOSIS: Authentication failure" >&2
        echo "  - Check B2_ACCOUNT_ID and B2_ACCOUNT_KEY are correct" >&2
        echo "  - Verify the application key has proper permissions" >&2
        echo "  - Check if the key has expired or been revoked" >&2
    elif echo "$error_output" | grep -qi "connection.*refused\|connection.*timed out\|network.*unreachable\|no route to host\|temporary failure in name resolution"; then
        echo "DIAGNOSIS: Network connectivity issue" >&2
        echo "  - Check internet connection" >&2
        echo "  - Verify firewall/proxy settings" >&2
        echo "  - Check if B2 service is accessible" >&2
        echo "  - Try: curl -I https://api.backblazeb2.com" >&2
    elif echo "$error_output" | grep -qi "no space left on device\|disk.*full\|quota exceeded"; then
        echo "DIAGNOSIS: Disk space issue" >&2
        echo "  - Check available disk space: df -h" >&2
        echo "  - Clean up old files or increase storage" >&2
    elif echo "$error_output" | grep -qi "bucket.*not.*found\|repository does not exist\|404"; then
        echo "DIAGNOSIS: Repository not found" >&2
        echo "  - Check RESTIC_REPOSITORY is correct: $RESTIC_REPOSITORY" >&2
        echo "  - Verify the B2 bucket exists" >&2
        echo "  - Repository may need to be initialized first" >&2
    elif echo "$error_output" | grep -qi "snapshot.*not.*found\|no snapshot\|invalid.*id\|unknown snapshot"; then
        echo "DIAGNOSIS: Snapshot not found" >&2
        echo "  - No snapshots exist in repository yet" >&2
        echo "  - The specified snapshot ID may be invalid" >&2
        echo "  - List available snapshots: restic snapshots" >&2
    elif echo "$error_output" | grep -qi "wrong password\|incorrect.*password\|cannot.*decrypt"; then
        echo "DIAGNOSIS: Incorrect repository password" >&2
        echo "  - Check RESTIC_PASSWORD is correct" >&2
        echo "  - Ensure password hasn't changed since repo creation" >&2
    elif echo "$error_output" | grep -qi "lock.*failed\|already locked\|unable to create lock"; then
        echo "DIAGNOSIS: Repository lock issue" >&2
        echo "  - Another operation may be running" >&2
        echo "  - Stale lock from previous failed operation" >&2
        echo "  - Manual unlock may be needed: restic unlock" >&2
    elif echo "$error_output" | grep -qi "permission denied\|access is denied"; then
        echo "DIAGNOSIS: File permission issue" >&2
        echo "  - Check write permissions on target directory" >&2
        echo "  - Verify user has access to: $RESTORE_DIR" >&2
    elif echo "$error_output" | grep -qi "rate limit\|too many requests\|429"; then
        echo "DIAGNOSIS: API rate limit exceeded" >&2
        echo "  - B2 is rate limiting requests" >&2
        echo "  - Wait and retry later" >&2
    elif echo "$error_output" | grep -qi "timeout\|timed out"; then
        echo "DIAGNOSIS: Operation timeout" >&2
        echo "  - Network connection may be slow" >&2
        echo "  - Large files may need more time" >&2
        echo "  - Check B2 service status" >&2
    else
        echo "DIAGNOSIS: Unknown error (see details below)" >&2
    fi
    
    echo "----------------------------------------" >&2
    echo "Full error output:" >&2
    echo "$error_output" >&2
    echo "========================================" >&2
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
            diagnose_error "$RESTORE_ERROR" "Restore operation" "$RESTORE_EXIT_CODE"
            mark_failure "Restore failed (exit $RESTORE_EXIT_CODE) - see logs for details"
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