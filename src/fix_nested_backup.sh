#!/bin/bash

# This script fixes the nested backup directory issue
# It should be run once to migrate from old backup structure to new structure

BACKUP_DIR="${BACKUP_SOURCE_DIR:-/backup}"

echo "==========================================" 
echo "🔧 Fixing nested backup directory structure"
echo "==========================================" 

# Check if nested backup directory exists
if [ -d "$BACKUP_DIR/backup" ]; then
    echo "Found nested backup directory at $BACKUP_DIR/backup"
    echo "Moving contents up one level..."
    
    # Create a temporary directory
    TEMP_DIR="/tmp/backup_fix_$$"
    mkdir -p "$TEMP_DIR"
    
    # Move nested backup contents to temp
    echo "Moving files to temporary location..."
    mv "$BACKUP_DIR/backup/"* "$TEMP_DIR/" 2>/dev/null || true
    mv "$BACKUP_DIR/backup/".* "$TEMP_DIR/" 2>/dev/null || true
    
    # Remove the now-empty nested backup directory
    rmdir "$BACKUP_DIR/backup" 2>/dev/null || rm -rf "$BACKUP_DIR/backup"
    
    # Move everything from temp back to backup root
    echo "Moving files back to $BACKUP_DIR..."
    mv "$TEMP_DIR/"* "$BACKUP_DIR/" 2>/dev/null || true
    mv "$TEMP_DIR/".* "$BACKUP_DIR/" 2>/dev/null || true
    
    # Clean up temp directory
    rmdir "$TEMP_DIR" 2>/dev/null || rm -rf "$TEMP_DIR"
    
    echo "✅ Fixed nested backup structure"
    echo "Files are now directly in $BACKUP_DIR"
    ls -la "$BACKUP_DIR"
else
    echo "✅ No nested backup directory found - structure is already correct"
fi

echo "==========================================" 
echo "🔄 Now running a fresh backup with corrected structure..."
echo "==========================================" 

# Run a new backup with the corrected structure
/src/backup.sh
