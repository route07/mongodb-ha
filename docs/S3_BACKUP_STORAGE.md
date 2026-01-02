# S3 Backup Storage Configuration

## Overview

The backup service can automatically copy encrypted backups to a mounted S3 storage drive (`~/s3-hel` on the host, mounted as `/mnt/s3-hel` in the container).

## Configuration

### Step 1: Mount S3 Storage

Ensure your S3 storage is mounted at `~/s3-hel` on the host:

```bash
# Verify S3 mount
ls -la ~/s3-hel
df -h | grep s3-hel
```

### Step 2: Configure Environment Variable

In your `.env` file:

```bash
# S3 Storage (mounted S3 drive)
BACKUP_S3_PATH=/mnt/s3-hel  # Path inside container
```

**Note**: The path `/mnt/s3-hel` is the container path. The host path `~/s3-hel` is automatically mounted via Docker volume.

### Step 3: Update Docker Compose

The `docker-compose.backup.yaml` already includes the S3 mount:

```yaml
volumes:
  - ~/s3-hel:/mnt/s3-hel:rw  # Mounted S3 storage
```

### Step 4: Restart Backup Service

```bash
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml restart mongodb-backup
```

## How It Works

1. **Backup is created** (MongoDB dump → compress → encrypt)
2. **Copy to S3** - Encrypted backup is copied to `/mnt/s3-hel` (which maps to `~/s3-hel` on host)
3. **Upload to IPFS** - Backup is also uploaded to IPFS (existing functionality)
4. **Both locations** - Backup exists in both S3 and IPFS

## Backup Workflow

```
MongoDB Dump
    ↓
Compress (gzip)
    ↓
Encrypt (AES-256-GCM)
    ↓
    ├─→ Copy to S3 (~/s3-hel) ✅ NEW
    └─→ Upload to IPFS ✅ Existing
```

## File Naming

Backups in S3 storage use the same naming convention:

- **Full Backup**: `full_backup_2024-01-14T02-00-00-000Z.tar.gz.enc`
- **Incremental Backup**: `incremental_backup_2024-01-15T02-00-00-000Z.tar.gz.enc`

## Benefits

✅ **Fast Recovery** - Direct access to backups from S3 mount  
✅ **Redundancy** - Backups in both S3 and IPFS  
✅ **No Additional Cost** - Uses existing S3 mount  
✅ **Automatic** - No manual intervention needed  

## Verification

### Check S3 Backup Files

```bash
# On host
ls -lh ~/s3-hel/

# Check from container
docker exec mongodb-backup ls -lh /mnt/s3-hel/
```

### Check Backup Logs

```bash
docker logs mongodb-backup | grep -i "s3"
```

You should see:
```
Step 4/7: Copying backup to S3 storage
Backup copied to S3 storage { s3Path: '/mnt/s3-hel/full_backup_...', size: ..., sizeMB: '...' }
```

## Troubleshooting

### Issue: S3 Copy Fails

**Symptom**: Logs show "Failed to copy backup to S3 storage"

**Check**:
1. S3 mount is accessible: `ls ~/s3-hel`
2. Container has write permissions: `docker exec mongodb-backup touch /mnt/s3-hel/test && rm /mnt/s3-hel/test`
3. Disk space available: `df -h ~/s3-hel`

**Note**: S3 copy failures don't stop the backup - IPFS upload still happens.

### Issue: S3 Path Not Configured

**Symptom**: No S3 copy happens (no error, just skipped)

**Fix**: Set `BACKUP_S3_PATH=/mnt/s3-hel` in `.env` and restart container.

### Issue: Permission Denied

**Symptom**: "EACCES: permission denied" when copying

**Fix**: Ensure S3 mount has write permissions:
```bash
chmod 755 ~/s3-hel
# Or adjust ownership if needed
```

## Disabling S3 Copy

To disable S3 copy (only use IPFS):

```bash
# In .env
# Don't set BACKUP_S3_PATH, or set it to empty
BACKUP_S3_PATH=
```

Or remove the volume mount from `docker-compose.backup.yaml`.

## Summary

- ✅ **Automatic** - Backups are copied to S3 after encryption
- ✅ **Non-blocking** - S3 copy failures don't stop backup
- ✅ **Redundant** - Backups in both S3 and IPFS
- ✅ **Configurable** - Set `BACKUP_S3_PATH` to enable/disable

The S3 copy happens automatically for both full and incremental backups!
