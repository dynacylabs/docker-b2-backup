#!/bin/bash

# Handle user/group ID mapping for file permissions
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# Function to run as root if needed for user management
run_as_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "Error: Need root privileges to change user/group IDs"
        exit 1
    fi
}

# Check if we need to update user/group IDs
if [ "$PUID" != "1000" ] || [ "$PGID" != "1000" ]; then
    echo "Updating user/group IDs to PUID=$PUID, PGID=$PGID"
    
    # We need root to change user/group IDs
    if [ "$(id -u)" != "0" ]; then
        echo "Warning: Cannot change user/group IDs - not running as root"
        echo "Consider using docker-compose user directive or running container as root initially"
    else
        # Update group
        if [ "$PGID" != "1000" ]; then
            groupmod -g "$PGID" backup || groupadd -g "$PGID" backup
        fi
        
        # Update user
        if [ "$PUID" != "1000" ]; then
            usermod -u "$PUID" -g "$PGID" backup 2>/dev/null || useradd -u "$PUID" -g "$PGID" -s /bin/bash backup
        fi
        
        # Fix ownership of directories
        chown -R backup:backup /var/log /src 2>/dev/null || true
    fi
fi

# Ensure backup source directory has correct permissions
BACKUP_SOURCE_DIR="${BACKUP_SOURCE_DIR:-/backup}"
if [ -d "$BACKUP_SOURCE_DIR" ]; then
    chown backup:backup "$BACKUP_SOURCE_DIR" 2>/dev/null || true
fi

# Default cron schedules
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"
RESTORE_CHECK_SCHEDULE="${RESTORE_CHECK_SCHEDULE:-0 1 * * *}"

echo "🔍 Debug: Environment variables:"
echo "BACKUP_SOURCE_DIR: ${BACKUP_SOURCE_DIR}"
echo "BACKUP_SCHEDULE: ${BACKUP_SCHEDULE}"
echo "RESTORE_CHECK_SCHEDULE: ${RESTORE_CHECK_SCHEDULE}"

# Function to setup and run as backup user
setup_and_run() {
    # Determine effective user
    if [ "$(id -u)" = "0" ]; then
        EFFECTIVE_USER="backup"
        echo "Running as root, will execute commands as backup user"
    else
        EFFECTIVE_USER="$(whoami)"
        echo "Running as non-root user: $EFFECTIVE_USER"
    fi
    
    # Create dynamic crontab based on environment variables
    CRON_FILE="/var/spool/cron/crontabs/backup"
    
    # Ensure cron directories exist
    mkdir -p /var/spool/cron/crontabs /var/log
    chmod 755 /var/spool/cron/crontabs
    
    # Export all environment variables to a file that cron can source
    echo "Creating environment file for cron jobs..."
    cat > /etc/environment << EOF
export RESTIC_REPOSITORY="${RESTIC_REPOSITORY}"
export RESTIC_PASSWORD="${RESTIC_PASSWORD}"
export B2_ACCOUNT_ID="${B2_ACCOUNT_ID}"
export B2_ACCOUNT_KEY="${B2_ACCOUNT_KEY}"
export BACKUP_SOURCE_DIR="${BACKUP_SOURCE_DIR}"
export BACKUP_TEMP_DIR="${BACKUP_TEMP_DIR:-/tmp/backup}"
export RESTIC_KEEP_DAILY="${RESTIC_KEEP_DAILY:-7}"
export RESTIC_KEEP_WEEKLY="${RESTIC_KEEP_WEEKLY:-4}"
export RESTIC_KEEP_MONTHLY="${RESTIC_KEEP_MONTHLY:-6}"
export RESTIC_KEEP_YEARLY="${RESTIC_KEEP_YEARLY:-2}"
EOF
    chmod 644 /etc/environment
    
    # Create crontab content
    cat > /tmp/crontab.tmp << EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Backup schedule (configurable via BACKUP_SCHEDULE)
${BACKUP_SCHEDULE} . /etc/environment && /src/backup.sh >> /var/log/backup.log 2>&1
# Restore check schedule (configurable via RESTORE_CHECK_SCHEDULE)
${RESTORE_CHECK_SCHEDULE} . /etc/environment && [ -z "\$(ls -A ${BACKUP_SOURCE_DIR})" ] && /src/restore.sh >> /var/log/restore.log 2>&1
EOF

    # Install the crontab directly to the spool directory
    if [ "$(id -u)" = "0" ]; then
        echo "Installing crontab for backup user..."
        cp /tmp/crontab.tmp "$CRON_FILE"
        chown backup:backup "$CRON_FILE"
        chmod 600 "$CRON_FILE"
        echo "Crontab installed directly to $CRON_FILE"
    else
        # Running as non-root, try standard crontab command
        crontab /tmp/crontab.tmp 2>/dev/null || echo "Failed to install crontab"
    fi
    
    # Clean up temp file
    rm -f /tmp/crontab.tmp

    # Create log directory with proper permissions
    mkdir -p /var/log 2>/dev/null || true
    touch /var/log/backup.log /var/log/restore.log /var/log/crond.log 2>/dev/null || true
    if [ "$(id -u)" = "0" ]; then
        chown backup:backup /var/log /var/log/backup.log /var/log/restore.log /var/log/crond.log 2>/dev/null || true
        chmod 666 /var/log/backup.log /var/log/restore.log /var/log/crond.log 2>/dev/null || true
    fi
    
    # Check if this is the first run (directory is empty)
    if [ -z "$(ls -A ${BACKUP_SOURCE_DIR} 2>/dev/null)" ]; then
        echo "Mounted directory is empty. Restoring from Backblaze B2..."
        if [ "$(id -u)" = "0" ]; then
            su backup -c "/src/restore.sh" 2>/dev/null || /src/restore.sh
        else
            /src/restore.sh
        fi
    fi

    # Start cron in foreground
    echo "Starting cron with the following schedule:"
    echo "Backup: ${BACKUP_SCHEDULE}"
    echo "Restore check: ${RESTORE_CHECK_SCHEDULE}"
    echo "Running as user: $EFFECTIVE_USER (UID=$(id -u), GID=$(id -g))"
    
    if [ "$(id -u)" = "0" ]; then
        # Show the crontab for backup user
        echo "Checking crontab installation..."
        if [ -f "/var/spool/cron/crontabs/backup" ]; then
            echo "✅ Crontab file exists for backup user"
            cat /var/spool/cron/crontabs/backup
        else
            echo "❌ Crontab file not found"
        fi
        
        # Start crond as root (it will run jobs as the specified users)
        echo "Starting crond as root daemon..."
        
        # Alpine's dcron needs specific flags:
        # -f: foreground mode
        # -d: debug level (8 is verbose, can be reduced to 0-7)
        # -l: log level
        # -L: log file
        
        # Start crond in foreground with logging
        exec crond -f -d 8 -L /var/log/crond.log
    else
        # Show current user's crontab
        echo "Current user's crontab:"
        crontab -l 2>/dev/null || echo "Crontab installed successfully"
        # Start crond as current user in foreground
        exec crond -f -d 8
    fi
}

# Run the setup
setup_and_run