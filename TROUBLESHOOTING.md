# Troubleshooting Common Issues

## Issue: Permission denied errors and user switching problems

### Symptoms:
```
Warning: Cannot change user/group IDs - not running as root
whoami: unknown uid 1003
crontab: Permission denied
crond: Permission denied
```

### Root Cause:
Container is not starting as root, so it can't perform user switching or cron operations.

### Solutions:

#### Option 1: Fix docker-compose.yml (Recommended)
```yaml
services:
  backup:
    user: "0:0"  # Start as root to allow user switching
    # ... rest of config
```

#### Option 2: Use direct user assignment
```yaml
services:
  backup:
    user: "${PUID:-1000}:${PGID:-1000}"  # Run directly as specified user
    # Remove user switching logic from container
```

## Issue: B2 Authentication failure (401 error)

### Symptoms:
```
Fatal: unable to open repository at b2:myservices-data:/: b2.NewClient: b2_authorize_account: 401
```

### Root Cause:
Invalid Backblaze B2 credentials or incorrect repository path.

### Solutions:

1. **Check your .env file:**
   ```bash
   cat .env
   ```

2. **Verify B2 credentials:**
   ```bash
   # Test credentials manually
   export B2_ACCOUNT_ID=your-account-id
   export B2_ACCOUNT_KEY=your-application-key
   
   # Test with restic
   export RESTIC_REPOSITORY=b2:bucket-name:path
   export RESTIC_PASSWORD=your-password
   restic init
   ```

3. **Common fixes:**
   - Ensure B2_ACCOUNT_ID and B2_ACCOUNT_KEY are correct
   - Check that the bucket exists and is accessible
   - Verify the repository path format: `b2:bucket-name:path`
   - Ensure the application key has the right permissions

## Issue: Wrong backup directory

### Symptoms:
```
ls: /backup: No such file or directory
```

### Root Cause:
Environment variable mismatch between expected and actual backup directory.

### Solution:
```bash
# In your .env file, ensure:
BACKUP_SOURCE_DIR=/mnt/backup

# And in docker-compose.yml:
volumes:
  - ./data:/mnt/backup  # Must match BACKUP_SOURCE_DIR
```

## Issue: Container restart loop

### Symptoms:
Container keeps restarting with the same errors repeatedly.

### Solutions:

1. **Stop the container:**
   ```bash
   docker stop docker-b2-backup
   ```

2. **Fix the configuration issues above**

3. **Remove the container:**
   ```bash
   docker rm docker-b2-backup
   ```

4. **Restart with correct configuration:**
   ```bash
   docker-compose up -d
   ```

## Quick Fix Commands

```bash
# Stop and remove container
docker stop docker-b2-backup && docker rm docker-b2-backup

# Check your environment file
cat .env

# Rebuild and restart with correct config
docker-compose up -d

# Monitor logs
docker logs -f docker-b2-backup
```

## Environment File Template

Create a proper `.env` file:

```bash
# Restic Configuration
RESTIC_REPOSITORY=b2:your-bucket-name:backup-path
RESTIC_PASSWORD=your-secure-restic-password

# Backblaze B2 Credentials
B2_ACCOUNT_ID=your-b2-account-id
B2_ACCOUNT_KEY=your-b2-application-key

# User Configuration
PUID=1003
PGID=1000

# Backup Configuration
BACKUP_SOURCE_DIR=/mnt/backup
BACKUP_TEMP_DIR=/tmp/backup
```

## Testing B2 Connection

Test your B2 connection outside the container:

```bash
# Install restic locally
sudo apt install restic  # or appropriate package manager

# Set environment variables
export RESTIC_REPOSITORY=b2:your-bucket:path
export RESTIC_PASSWORD=your-password
export B2_ACCOUNT_ID=your-account-id
export B2_ACCOUNT_KEY=your-app-key

# Test repository access
restic snapshots

# If repository doesn't exist, initialize it
restic init
```