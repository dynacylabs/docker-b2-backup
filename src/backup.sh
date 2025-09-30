#!/bin/bash

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

# Check if the mounted directory is empty
if [ -z "$(ls -A $MOUNTED_DIR)" ]; then
    echo "Mounted directory is empty. Restoring the latest backup from Backblaze B2..."
    /restore.sh
else
    echo "Starting backup process..."
    
    # Create a temporary directory
    mkdir -p $TEMP_DIR

    # Use rsync to copy files to the temporary directory
    rsync -a --delete $MOUNTED_DIR/ $TEMP_DIR/

    # Set the Restic environment variables
    export RESTIC_REPOSITORY
    export RESTIC_PASSWORD

    # Initialize the Restic repository if it doesn't exist
    restic init || true

    # Backup the temporary directory to Backblaze B2
    restic backup $TEMP_DIR

    # Clean up old snapshots based on retention policy
    KEEP_DAILY="${RESTIC_KEEP_DAILY:-7}"
    KEEP_WEEKLY="${RESTIC_KEEP_WEEKLY:-4}"
    KEEP_MONTHLY="${RESTIC_KEEP_MONTHLY:-6}"
    KEEP_YEARLY="${RESTIC_KEEP_YEARLY:-2}"

    echo "Cleaning up old snapshots (keeping: ${KEEP_DAILY} daily, ${KEEP_WEEKLY} weekly, ${KEEP_MONTHLY} monthly, ${KEEP_YEARLY} yearly)..."
    restic forget --keep-daily $KEEP_DAILY --keep-weekly $KEEP_WEEKLY --keep-monthly $KEEP_MONTHLY --keep-yearly $KEEP_YEARLY --prune

    # Cleanup temporary directory
    rm -rf $TEMP_DIR

    echo "Backup completed successfully."
fi