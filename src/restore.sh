#!/bin/bash

# Define variables from environment with defaults
RESTORE_DIR="${BACKUP_SOURCE_DIR:-/mnt/backup}"
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
    
    # Restore the latest backup from Backblaze B2
    restic restore latest --target $RESTORE_DIR
    
    echo "Restore completed."
else
    echo "Restore directory is not empty. No restore action taken."
fi