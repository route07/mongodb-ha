# S3 Backup Storage Configuration

## Overview

The backup service can automatically copy encrypted backups to a mounted S3 storage drive. The S3 mount should already exist on your host system.

## Configuration

### Step 1: Verify S3 Mount Exists

Ensure your S3 storage is mounted on the host:

```bash
# Check if S3 mount exists
ls -la /home/tschain/s3-hel
df -h | grep s3-hel
```

### Step 2: Configure Environment Variables

In your `.env` file:

```bash
# S3 Storage Configuration
BACKUP_S3_HOST_PATH=/home/tschain/s3-hel  # Host path (absolute path on your server)
BACKUP_S3_PATH=/mnt/s3-hel                # Container path (don't change this)
```

**Important**:
- `BACKUP_S3_HOST_PATH` = Path on your **host/server** (where S3 is mounted)
- `BACKUP_S3_PATH` = Path **inside container** (always `/mnt/s3-hel`)

### Step 3: Docker Compose Configuration

The `docker-compose.backup.yaml` automatically uses `BACKUP_S3_HOST_PATH`:

```yaml
volumes:
  - ${BACKUP_S3_HOST_PATH:-/home/tschain/s3-hel}:/mnt/s3-hel:rw
```

This maps:
- **Host**: `/home/tschain/s3-hel` (or whatever you set in `BACKUP_S3_HOST_PATH`)
- **Container**: `/mnt/s3-hel`

### Step 4: Restart Backup Service

```bash
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml restart mongodb-backup
```

## How It Works

1. **Backup is created** (MongoDB dump → compress → encrypt)
2. **Copy to S3** - Encrypted backup is copied to `/mnt/s3-hel` inside container
3. **Maps to host** - Container path `/mnt/s3-hel` maps to your host path (e.g., `/home/tschain/s3-hel`)
4. **Upload to IPFS** - Backup is also uploaded to IPFS (existing functionality)
5. **Both locations** - Backup exists in both S3 and IPFS

## Path Mapping

```
Host System              Docker Container
─────────────────        ─────────────────
/home/tschain/s3-hel  →   /mnt/s3-hel
     ↑                          ↑
  (S3 mount)              (BACKUP_S3_PATH)
```

## Troubleshooting

### Error: "file exists" or "directory already exists"

**Symptom**: Docker complains the directory already exists

**Cause**: Docker tries to create the directory, but it already exists (which is correct - it's your S3 mount)

**Solution**: Use an **absolute path** in `BACKUP_S3_HOST_PATH`:

```bash
# In .env
BACKUP_S3_HOST_PATH=/home/tschain/s3-hel  # Absolute path, not relative
```

**Don't use**:
- `~/s3-hel` (tilde expansion doesn't work in Docker Compose)
- `../s3-hel` (relative paths can cause issues)

### Verify Mount Works

```bash
# Test from container
docker exec mongodb-backup ls -la /mnt/s3-hel

# Test write permission
docker exec mongodb-backup touch /mnt/s3-hel/test-write
docker exec mongodb-backup rm /mnt/s3-hel/test-write
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

## File Naming

Backups in S3 storage use the same naming convention:

- **Full Backup**: `full_backup_2024-01-14T02-00-00-000Z.tar.gz.enc`
- **Incremental Backup**: `incremental_backup_2024-01-15T02-00-00-000Z.tar.gz.enc`

## Benefits

✅ **Fast Recovery** - Direct access to backups from S3 mount  
✅ **Redundancy** - Backups in both S3 and IPFS  
✅ **No Additional Cost** - Uses existing S3 mount  
✅ **Automatic** - No manual intervention needed  

## Disabling S3 Copy

To disable S3 copy (only use IPFS):

```bash
# In .env - don't set BACKUP_S3_HOST_PATH, or comment it out
# BACKUP_S3_HOST_PATH=/home/tschain/s3-hel
```

Or remove the volume mount from `docker-compose.backup.yaml`.

## Summary

- ✅ **Use absolute path** for `BACKUP_S3_HOST_PATH` (e.g., `/home/tschain/s3-hel`)
- ✅ **Container path** is always `/mnt/s3-hel` (set in `BACKUP_S3_PATH`)
- ✅ **Directory should exist** on host (it's your S3 mount)
- ✅ **Docker will mount it** - no need to create it

The "file exists" error is normal - your S3 mount already exists, which is correct!
