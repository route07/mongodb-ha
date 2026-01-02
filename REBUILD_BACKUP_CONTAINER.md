# Rebuild Backup Container for S3 Support

## Quick Rebuild

```bash
cd ~/ha-mongodb

# Rebuild the backup container
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml build mongodb-backup

# Restart with new image
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml up -d mongodb-backup
```

## Verify It Worked

After rebuilding, check the logs show the new step:

```bash
# Run a test backup
docker exec mongodb-backup node scripts/manual-backup.js full
```

**Look for**:
- ✅ "Step 4/7: Copying backup to S3 storage" (not "Step 4/6")
- ✅ "Backup copied to S3 storage" message
- ✅ File in `/home/tschain/s3-hel/`

## Check S3 Directory

```bash
# On host
ls -lh /home/tschain/s3-hel/

# Or from container
docker exec mongodb-backup ls -lh /mnt/s3-hel/
```

You should see the backup file: `full_backup_YYYY-MM-DDTHH-MM-SS-sssZ.tar.gz.enc`
