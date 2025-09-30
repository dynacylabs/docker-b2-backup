#!/bin/bash

# Default cron schedules
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 2 * * *}"
RESTORE_CHECK_SCHEDULE="${RESTORE_CHECK_SCHEDULE:-0 1 * * *}"
BACKUP_SOURCE_DIR="${BACKUP_SOURCE_DIR:-/mnt/backup}"

# Create dynamic crontab based on environment variables
cat > /tmp/crontab << EOF
SHELL=/bin/sh
# Backup schedule (configurable via BACKUP_SCHEDULE)
${BACKUP_SCHEDULE} /src/backup.sh >> /var/log/backup.log 2>&1
# Restore check schedule (configurable via RESTORE_CHECK_SCHEDULE)
${RESTORE_CHECK_SCHEDULE} [ -z "\$(ls -A ${BACKUP_SOURCE_DIR})" ] && /src/restore.sh >> /var/log/restore.log 2>&1
EOF

# Install the crontab
crontab /tmp/crontab

# Create log directory
mkdir -p /var/log

# Check if this is the first run (directory is empty)
if [ -z "$(ls -A ${BACKUP_SOURCE_DIR})" ]; then
    echo "Mounted directory is empty. Restoring from Backblaze B2..."
    /src/restore.sh
fi

# Start cron in foreground
echo "Starting cron with the following schedule:"
echo "Backup: ${BACKUP_SCHEDULE}"
echo "Restore check: ${RESTORE_CHECK_SCHEDULE}"
crontab -l
exec crond -f