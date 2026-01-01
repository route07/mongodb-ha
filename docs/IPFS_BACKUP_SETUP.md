# IPFS Backup Setup Guide

Step-by-step guide to set up IPFS backups for your HA MongoDB setup.

## Prerequisites

1. ✅ HA MongoDB replica set running
2. ✅ IPFS cluster with 2 nodes accessible
3. ✅ Private network connectivity between MongoDB and IPFS nodes

## Setup Steps

### Step 1: Generate Encryption Key

```bash
# Generate a 256-bit encryption key
openssl rand -base64 32
```

**Save this key securely!** You'll need it for:
- Configuration
- Restoring backups
- Key rotation

Example output:
```
K8j3mN9pQ2rT5vX7zA1bC4dE6fG8hI0jK2mN4pQ6rT8vX0zA2bC4dE6fG8hI=
```

### Step 2: Configure Environment Variables

Edit your `.env` file and add:

```bash
# Encryption Key (REQUIRED)
BACKUP_ENCRYPTION_KEY=K8j3mN9pQ2rT5vX7zA1bC4dE6fG8hI0jK2mN4pQ6rT8vX0zA2bC4dE6fG8hI=

# IPFS Cluster Nodes (REQUIRED)
# Replace with your actual IPFS node URLs
IPFS_NODE_1_URL=http://ipfs-node-1.internal:5001
IPFS_NODE_2_URL=http://ipfs-node-2.internal:5001
IPFS_REPLICATION_FACTOR=2

# Backup Schedule (Optional - defaults shown)
FULL_BACKUP_SCHEDULE=0 2 * * 0      # Sunday 2 AM UTC
INCREMENTAL_BACKUP_SCHEDULE=0 2 * * *  # Daily 2 AM UTC
BACKUP_RETENTION_DAYS=90

# Local Storage (Optional)
BACKUP_LOCAL_RETENTION_DAYS=7

# Webhook Notifications (Optional)
WEBHOOK_URL=https://your-webhook-url.com/backup-notifications
WEBHOOK_ENABLED=true

# Logging (Optional)
LOG_LEVEL=info
```

### Step 3: Verify IPFS Connectivity

Test connectivity to your IPFS nodes:

```bash
# Test Node 1
curl http://ipfs-node-1.internal:5001/api/v0/version

# Test Node 2
curl http://ipfs-node-2.internal:5001/api/v0/version
```

Both should return IPFS version information.

### Step 4: Start Backup Service

```bash
# Build and start backup service
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml up -d --build mongodb-backup

# Or if you've added it to your main docker-compose.yaml
docker-compose up -d --build mongodb-backup
```

### Step 5: Verify Service is Running

```bash
# Check container status
docker ps | grep mongodb-backup

# Check logs
docker logs mongodb-backup

# Check health
docker exec mongodb-backup node -e "console.log('Service is running')"
```

You should see:
- Container running
- Logs showing service started
- IPFS connectivity check passed

### Step 6: Test Manual Backup

Trigger a manual backup to test:

```bash
# Connect to container
docker exec -it mongodb-backup sh

# Run full backup manually (if you add a manual trigger script)
# Or wait for scheduled backup
```

### Step 7: Verify Backup

After first backup completes:

```bash
# List backups
docker exec mongodb-backup node restore/restore.js list

# Check manifest
docker exec mongodb-backup cat /data/backups/manifest.json

# Verify IPFS pin
# (Check your IPFS cluster dashboard or use IPFS CLI)
```

## Verification Checklist

- [ ] Encryption key generated and configured
- [ ] IPFS nodes accessible from backup container
- [ ] Backup service container running
- [ ] First backup completed successfully
- [ ] Backup visible in manifest
- [ ] Backup pinned on both IPFS nodes
- [ ] Webhook notifications working (if configured)
- [ ] Logs show no errors

## Testing Restore

### Test Full Restore

```bash
# 1. List available backups
docker exec mongodb-backup node restore/restore.js list

# 2. Get a full backup CID
# (from the list output)

# 3. Test restore to a test database
docker exec mongodb-backup node restore/restore.js restore-full <CID> \
  --uri="mongodb://user:pass@mongodb-primary:27017/testdb?tls=true&tlsCAFile=/etc/mongo/ssl/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

## Monitoring

### View Logs

```bash
# Real-time logs
docker logs -f mongodb-backup

# Recent logs
docker logs --tail 100 mongodb-backup

# Log files (inside container)
docker exec mongodb-backup ls -la /var/log/backups
```

### Check Backup Status

```bash
# List all backups
docker exec mongodb-backup node restore/restore.js list

# Check statistics
docker exec mongodb-backup node -e "
  const manifest = require('./src/manifest/manager');
  manifest.getStatistics().then(s => console.log(JSON.stringify(s, null, 2)));
"
```

### Verify IPFS Pins

Check your IPFS cluster dashboard or use IPFS CLI to verify backups are pinned.

## Troubleshooting

### Service Won't Start

1. **Check environment variables**:
   ```bash
   docker exec mongodb-backup env | grep BACKUP
   docker exec mongodb-backup env | grep IPFS
   ```

2. **Check MongoDB connectivity**:
   ```bash
   docker exec mongodb-backup mongosh "${MONGODB_URI}" --eval "db.adminCommand('ping')"
   ```

3. **Check IPFS connectivity**:
   ```bash
   docker exec mongodb-backup node -e "
     const {create} = require('ipfs-http-client');
     create({url: process.env.IPFS_NODE_1_URL}).id().then(console.log).catch(console.error);
   "
   ```

### Backup Fails

1. **Check MongoDB permissions**: Ensure backup user can read from secondary
2. **Check disk space**: Ensure enough space for backups
3. **Check IPFS cluster**: Verify nodes are healthy and accessible
4. **Check logs**: `docker logs mongodb-backup`

### IPFS Upload Fails

1. **Verify IPFS nodes are accessible**:
   ```bash
   curl http://ipfs-node-1.internal:5001/api/v0/version
   curl http://ipfs-node-2.internal:5001/api/v0/version
   ```

2. **Check IPFS cluster status**:
   - Verify nodes are in cluster
   - Check replication factor configuration
   - Verify cluster has enough storage

### Encryption Errors

1. **Verify key format**:
   ```bash
   # Key should be base64 and decode to 32 bytes
   echo "${BACKUP_ENCRYPTION_KEY}" | base64 -d | wc -c
   # Should output: 32
   ```

2. **Regenerate key if needed**:
   ```bash
   openssl rand -base64 32
   ```

## Maintenance

### Update Backup Schedule

Edit `.env` and restart service:
```bash
docker-compose restart mongodb-backup
```

### Change Retention Policy

Edit `BACKUP_RETENTION_DAYS` in `.env` and restart:
```bash
docker-compose restart mongodb-backup
```

### Rotate Encryption Key

⚠️ **Warning**: Rotating keys requires re-encrypting all backups or accepting that old backups cannot be decrypted.

1. Generate new key
2. Update `BACKUP_ENCRYPTION_KEY` in `.env`
3. Restart service
4. New backups will use new key
5. Old backups remain encrypted with old key

## Next Steps

- [ ] Set up monitoring/alerting for backup failures
- [ ] Test restore procedure monthly
- [ ] Document recovery procedures for your team
- [ ] Set up backup verification tests
- [ ] Configure webhook notifications

## Support

For issues or questions:
1. Check logs: `docker logs mongodb-backup`
2. Review [Troubleshooting Guide](./IPFS_BACKUP_STRATEGY.md#troubleshooting)
3. Check [Implementation Guide](./IPFS_BACKUP_IMPLEMENTATION.md)
