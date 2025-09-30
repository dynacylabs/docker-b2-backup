#!/bin/bash

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
    exit 1
fi

if [ -z "$RESTIC_PASSWORD" ]; then
    echo "Error: RESTIC_PASSWORD environment variable is required"
    exit 1
fi

if [ -z "$B2_ACCOUNT_ID" ] || [ -z "$B2_ACCOUNT_KEY" ]; then
    echo "Error: B2_ACCOUNT_ID and B2_ACCOUNT_KEY environment variables are required"
    exit 1
fi

# Set the Restic environment variables
export RESTIC_REPOSITORY
export RESTIC_PASSWORD

# Check if the restore directory is empty
if [ -z "$(ls -A $RESTORE_DIR)" ]; then
    echo "Restore directory is empty. Restoring the latest backup from Backblaze B2..."
    
    # Create a temporary restore directory
    TEMP_RESTORE="/tmp/restore_temp"
    mkdir -p "$TEMP_RESTORE"
    
    # Restore the latest backup to temporary directory
    restic restore latest --target "$TEMP_RESTORE"
    
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
    
    echo "Restore completed."
else
    echo "Restore directory is not empty. No restore action taken."
fi