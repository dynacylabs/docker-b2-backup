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
BACKUP_SOURCE_DIR="${BACKUP_SOURCE_DIR:-/mnt/backup}"
if [ -d "$BACKUP_SOURCE_DIR" ]; then
    chown backup:backup "$BACKUP_SOURCE_DIR" 2>/dev/null || true
fi

# Default cron schedules
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"
RESTORE_CHECK_SCHEDULE="${RESTORE_CHECK_SCHEDULE:-0 1 * * *}"

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
    cat > /tmp/crontab << EOF
SHELL=/bin/sh
# Backup schedule (configurable via BACKUP_SCHEDULE)
${BACKUP_SCHEDULE} /src/backup.sh >> /var/log/backup.log 2>&1
# Restore check schedule (configurable via RESTORE_CHECK_SCHEDULE)
${RESTORE_CHECK_SCHEDULE} [ -z "\$(ls -A ${BACKUP_SOURCE_DIR})" ] && /src/restore.sh >> /var/log/restore.log 2>&1
EOF

    # Install the crontab
    if [ "$(id -u)" = "0" ]; then
        # Running as root, install crontab for backup user
        echo "Installing crontab for backup user..."
        su backup -c "/usr/bin/crontab /tmp/crontab" 2>/dev/null || \
        su backup -c "crontab /tmp/crontab" 2>/dev/null || \
        (chown backup:backup /tmp/crontab && su backup -c "crontab /tmp/crontab")
    else
        # Running as non-root, install directly
        /usr/bin/crontab /tmp/crontab 2>/dev/null || crontab /tmp/crontab
    fi

    # Create log directory with proper permissions
    mkdir -p /var/log 2>/dev/null || true
    if [ "$(id -u)" = "0" ]; then
        chown backup:backup /var/log 2>/dev/null || true
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
        su backup -c "/usr/bin/crontab -l" 2>/dev/null || \
        su backup -c "crontab -l" 2>/dev/null || \
        echo "Crontab installed successfully"
        
        # Start crond as backup user
        echo "Starting crond as backup user..."
        exec su backup -c "/usr/sbin/crond -f" 2>/dev/null || \
        exec su backup -c "crond -f" 2>/dev/null || \
        exec /usr/sbin/crond -f 2>/dev/null || \
        exec crond -f
    else
        # Show current user's crontab
        /usr/bin/crontab -l 2>/dev/null || crontab -l 2>/dev/null || echo "Crontab installed successfully"
        # Start crond as current user
        exec /usr/sbin/crond -f 2>/dev/null || exec crond -f
    fi
}

# Run the setup
setup_and_run