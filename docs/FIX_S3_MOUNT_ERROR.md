# Fix: Docker "file exists" Error for S3 Mount

## The Problem

Docker Compose tries to create the S3 mount directory, but it already exists (as a mount point), causing:

```
Error response from daemon: error while creating mount source path '/home/tschain/s3-hel': mkdir /home/tschain/s3-hel: file exists
```

## Solution Options

### Option 1: Use a Subdirectory (Recommended)

Instead of mounting the root S3 directory, use a subdirectory:

**Step 1: Create subdirectory in S3 mount**

```bash
mkdir -p /home/tschain/s3-hel/mongodb-backups
```

**Step 2: Update `.env`**

```bash
BACKUP_S3_HOST_PATH=/home/tschain/s3-hel/mongodb-backups
BACKUP_S3_PATH=/mnt/s3-hel
```

**Step 3: Update docker-compose.backup.yaml**

The volume mount will automatically use the subdirectory.

**Why this works**: Docker Compose can create the subdirectory structure if needed, but the parent (`/home/tschain/s3-hel`) already exists as a mount point.

### Option 2: Pre-create with Correct Permissions

Ensure the directory exists with proper permissions before Docker tries to access it:

```bash
# Ensure directory exists and is accessible
sudo mkdir -p /home/tschain/s3-hel
sudo chown $USER:$USER /home/tschain/s3-hel
sudo chmod 755 /home/tschain/s3-hel

# Verify it's accessible
ls -la /home/tschain/s3-hel
```

### Option 3: Use Docker Run Instead of Compose (Temporary Workaround)

If Docker Compose continues to have issues, you can start the container manually:

```bash
docker run -d \
  --name mongodb-backup \
  --network ha-mongodb_db-network \
  -v /home/tschain/s3-hel:/mnt/s3-hel:rw \
  -v $(pwd)/tls-certs:/etc/mongo/ssl:ro \
  # ... other volumes and env vars
  mongodb-backup
```

### Option 4: Check Docker Compose Version

Older versions of Docker Compose have issues with existing mount points. Update if needed:

```bash
# Check version
docker-compose --version

# Update if needed (example for Linux)
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

## Recommended Solution

**Use Option 1 (subdirectory)** - it's the cleanest and most reliable:

1. Create subdirectory: `mkdir -p /home/tschain/s3-hel/mongodb-backups`
2. Update `.env`: `BACKUP_S3_HOST_PATH=/home/tschain/s3-hel/mongodb-backups`
3. Restart: `docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml up -d mongodb-backup`

## Verification

After applying the fix:

```bash
# Check container starts
docker ps | grep mongodb-backup

# Verify S3 mount works
docker exec mongodb-backup ls -la /mnt/s3-hel

# Test write
docker exec mongodb-backup touch /mnt/s3-hel/test && docker exec mongodb-backup rm /mnt/s3-hel/test
```

## Why This Happens

Docker Compose tries to create parent directories for bind mounts. When the directory is a mount point (like an S3 mount), Docker's directory creation logic can conflict with the existing mount point, causing the "file exists" error even though the directory should be usable.

Using a subdirectory avoids this because:
- The parent directory (`/home/tschain/s3-hel`) already exists as a mount
- Docker doesn't need to create it
- The subdirectory (`mongodb-backups`) can be created if needed, or already exists
