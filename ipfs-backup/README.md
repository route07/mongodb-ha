# MongoDB IPFS Backup Service

Automated MongoDB backup service that backs up your HA MongoDB replica set to IPFS with encryption.

## Features

- ✅ **Full Backups**: Weekly complete database backups
- ✅ **Incremental Backups**: Daily oplog-based incremental backups
- ✅ **Encryption**: AES-256-GCM encryption before IPFS upload
- ✅ **IPFS Integration**: Automatic upload and pinning on IPFS cluster
- ✅ **Retention Policy**: Automatic cleanup of backups older than 90 days
- ✅ **Local Storage**: Keeps encrypted backups locally for fast recovery
- ✅ **Webhook Notifications**: Sends backup status to webhook URL
- ✅ **Manifest Tracking**: Tracks all backups with metadata in IPFS

## Quick Start

### 1. Generate Encryption Key

```bash
openssl rand -base64 32
```

Add this to your `.env` file as `BACKUP_ENCRYPTION_KEY`.

### 2. Configure Environment Variables

Add to your `.env` file:

```bash
# Encryption Key (REQUIRED)
BACKUP_ENCRYPTION_KEY=<your-generated-key>

# IPFS Cluster Nodes (REQUIRED)
IPFS_NODE_1_URL=http://ipfs-node-1.internal:5001
IPFS_NODE_2_URL=http://ipfs-node-2.internal:5001

# Webhook (Optional)
WEBHOOK_URL=https://your-webhook-url.com/backup-notifications
WEBHOOK_ENABLED=true
```

### 3. Start Backup Service

```bash
# Using docker-compose
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml up -d mongodb-backup

# Or add to existing docker-compose.yaml
docker-compose up -d mongodb-backup
```

## Configuration

### Backup Schedule

- **Full Backup**: Default `0 2 * * 0` (Sunday 2 AM UTC)
- **Incremental Backup**: Default `0 2 * * *` (Daily 2 AM UTC)
- **Retention Cleanup**: 30 minutes after backup

### Environment Variables

See `.env.example` for all available configuration options.

## Backup Workflow

1. **Connect** to MongoDB secondary (read preference)
2. **Dump** all databases using `mongodump`
3. **Compress** backup directory to tar.gz
4. **Encrypt** backup using AES-256-GCM
5. **Upload** to IPFS and get CID
6. **Pin** on both IPFS nodes (replication factor 2)
7. **Update** manifest with backup metadata
8. **Store** encrypted backup locally (for fast recovery)
9. **Cleanup** old backups (retention policy)

## Restore Backups

### List Available Backups

```bash
docker exec mongodb-backup node restore/restore.js list
```

### Full Restore Workflow

```bash
# Download, decrypt, extract, and restore in one command
docker exec mongodb-backup node restore/restore.js restore-full <CID> \
  --uri="mongodb://user:pass@host:27017/?tls=true&tlsCAFile=/etc/mongo/ssl/ca.crt"
```

### Manual Restore Steps

```bash
# 1. List backups
docker exec mongodb-backup node restore/restore.js list

# 2. Download from IPFS
docker exec mongodb-backup node restore/restore.js download <CID> -o backup.tar.gz.enc

# 3. Decrypt
docker exec mongodb-backup node restore/restore.js decrypt backup.tar.gz.enc -o backup.tar.gz

# 4. Extract
tar -xzf backup.tar.gz

# 5. Restore to MongoDB
docker exec mongodb-backup node restore/restore.js restore <extracted-dir> \
  --uri="mongodb://user:pass@host:27017/?tls=true&tlsCAFile=/etc/mongo/ssl/ca.crt"
```

## Backup Structure

### Full Backup
- Contains all databases
- Format: `full_backup_YYYY-MM-DD_HHMMSS.tar.gz.enc`
- Stored locally and in IPFS

### Incremental Backup
- Contains oplog entries since last backup
- Format: `incremental_backup_YYYY-MM-DD_HHMMSS.tar.gz.enc`
- Requires full backup to restore

### Manifest
- Tracks all backups with metadata
- Stored in IPFS and locally
- Includes: CID, timestamp, size, type, databases

## Monitoring

### Logs

```bash
# View logs
docker logs mongodb-backup

# Follow logs
docker logs -f mongodb-backup

# View log files (inside container)
docker exec mongodb-backup ls -la /var/log/backups
```

### Health Check

The service includes a health check endpoint (if enabled) and logs all operations.

### Webhook Notifications

The service sends webhook notifications for:
- Backup success
- Backup failure
- Retention cleanup

Webhook payload format:
```json
{
  "type": "success|error|info",
  "title": "Backup Completed Successfully",
  "timestamp": "2024-01-15T02:00:00Z",
  "service": "mongodb-backup",
  "backupType": "full",
  "cid": "QmXxxx...",
  "size": 5242880,
  "duration": 45.2
}
```

## Troubleshooting

### Backup Fails

1. Check MongoDB connectivity:
   ```bash
   docker exec mongodb-backup mongosh "${MONGODB_URI}"
   ```

2. Check IPFS connectivity:
   ```bash
   docker exec mongodb-backup node -e "const {create} = require('ipfs-http-client'); create({url: process.env.IPFS_NODE_1_URL}).id().then(console.log)"
   ```

3. Check logs:
   ```bash
   docker logs mongodb-backup
   ```

### IPFS Pin Fails

- Verify IPFS nodes are accessible
- Check replication factor configuration
- Verify IPFS cluster is healthy

### Encryption Errors

- Verify `BACKUP_ENCRYPTION_KEY` is set correctly
- Key must be base64-encoded 32-byte (256-bit) key
- Generate new key: `openssl rand -base64 32`

## Security

- **Encryption**: All backups encrypted with AES-256-GCM
- **Key Management**: Encryption key stored in environment variable
- **Network**: All connections over private network
- **TLS**: MongoDB connections use TLS
- **File Permissions**: Encrypted backups have restricted permissions

## Retention Policy

- **IPFS**: Backups older than 90 days are unpinned
- **Local Storage**: Backups older than 7 days are deleted locally
- **Manifest**: Updated after each cleanup

## Development

### Local Development

```bash
cd ipfs-backup
npm install
cp .env.example .env
# Edit .env with your configuration
npm start
```

### Testing

```bash
npm test
```

## Architecture

See [IPFS_BACKUP_STRATEGY.md](../docs/IPFS_BACKUP_STRATEGY.md) for detailed architecture and design decisions.

## License

MIT
