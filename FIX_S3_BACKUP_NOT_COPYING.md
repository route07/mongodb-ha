# Fix: S3 Backup Not Copying

## The Problem

Backup completes successfully but nothing appears in S3 directory. Logs show "Step 4/6" instead of "Step 4/7", meaning S3 copy step is not executing.

## Causes

1. **Container needs rebuild** - Updated code with S3 copy isn't in the container
2. **Environment variable not set** - `BACKUP_S3_PATH` not configured
3. **Config not loading** - S3 path not being read correctly

## Solution

### Step 1: Check Environment Variable

```bash
# Check if BACKUP_S3_PATH is set in container
docker exec mongodb-backup printenv | grep BACKUP_S3_PATH
```

Should show: `BACKUP_S3_PATH=/mnt/s3-hel`

### Step 2: Rebuild Container (Required)

The container needs to be rebuilt to include the updated code:

```bash
cd ~/ha-mongodb

# Rebuild the backup container
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml build mongodb-backup

# Restart with new image
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml up -d mongodb-backup
```

### Step 3: Verify Configuration

Run the test script:

```bash
./scripts/test-s3-backup.sh
```

### Step 4: Test Manual Backup Again

```bash
docker exec mongodb-backup node scripts/manual-backup.js full
```

**Look for**: "Step 4/7: Copying backup to S3 storage" in the logs

## Expected Logs After Fix

```
Step 3/7: Encrypting backup
Backup encrypted { size: ..., sizeMB: '...' }
Step 4/7: Copying backup to S3 storage  ← Should see this!
Backup copied to S3 storage { s3Path: '/mnt/s3-hel/full_backup_...', ... }
Step 5/7: Uploading to IPFS
...
```

## Quick Fix Command

```bash
# Rebuild and restart
cd ~/ha-mongodb
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml build mongodb-backup
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml up -d mongodb-backup

# Wait a few seconds, then test
sleep 5
docker exec mongodb-backup node scripts/manual-backup.js full
```

## Verify S3 Copy Worked

```bash
# Check files in S3
ls -lh /home/tschain/s3-hel/

# Or from container
docker exec mongodb-backup ls -lh /mnt/s3-hel/
```

You should see the backup file: `full_backup_YYYY-MM-DDTHH-MM-SS-sssZ.tar.gz.enc`
