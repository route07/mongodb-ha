# IPFS Backup Implementation Guide

## Implementation Structure

### Directory Layout

```
ipfs-backup/
├── Dockerfile                    # Container definition
├── package.json                  # Node.js dependencies
├── .env.example                  # Environment template
├── .dockerignore
├── src/
│   ├── index.js                  # Main entry point & scheduler
│   ├── backup/
│   │   ├── full.js               # Full backup logic
│   │   ├── incremental.js        # Incremental backup logic
│   │   └── mongodb-dump.js       # MongoDB dump wrapper
│   ├── encryption/
│   │   ├── encrypt.js            # Encryption functions
│   │   ├── decrypt.js            # Decryption functions
│   │   └── key-management.js     # Key derivation & management
│   ├── ipfs/
│   │   ├── client.js             # IPFS client wrapper
│   │   ├── upload.js             # Upload & pin logic
│   │   └── cluster.js            # IPFS cluster operations
│   ├── manifest/
│   │   ├── manager.js            # Manifest CRUD operations
│   │   ├── storage.js            # Store manifest in IPFS & MongoDB
│   │   └── query.js              # Query backups by date/type
│   ├── retention/
│   │   ├── policy.js             # Retention rules
│   │   └── cleanup.js            # Delete old backups
│   ├── utils/
│   │   ├── logger.js             # Logging utility
│   │   ├── compression.js        # Compression helpers
│   │   └── validation.js         # Backup validation
│   └── config/
│       └── load.js               # Configuration loader
├── restore/
│   ├── restore.js                # Restore CLI tool
│   ├── download.js               # Download from IPFS
│   └── decrypt.js                # Decrypt backup
├── scripts/
│   ├── test-backup.sh            # Test backup workflow
│   ├── test-restore.sh           # Test restore workflow
│   └── verify-ipfs.sh            # Verify IPFS connectivity
└── README.md
```

## Key Implementation Details

### 1. MongoDB Backup (`backup/mongodb-dump.js`)

```javascript
// Pseudo-code structure
class MongoDBBackup {
  async createFullBackup(outputDir) {
    // Use mongodump to export all databases
    // Output: BSON files in directory structure
  }
  
  async createIncrementalBackup(outputDir, lastBackupTime) {
    // Use mongodump --oplog
    // Capture oplog entries since lastBackupTime
  }
  
  async getBackupMetadata() {
    // Get MongoDB version, replica set info, database list
  }
}
```

**Key Points**:
- Connect to secondary node (read preference)
- Use `mongodump` for BSON format (native, efficient)
- Capture metadata (version, databases, timestamp)
- Handle TLS connections properly

### 2. Encryption (`encryption/encrypt.js`)

```javascript
// Pseudo-code structure
class BackupEncryption {
  async encryptFile(inputPath, outputPath, key) {
    // AES-256-GCM encryption
    // Generate random IV (12 bytes)
    // Encrypt file
    // Prepend IV to encrypted data
    // Append auth tag
  }
  
  async decryptFile(inputPath, outputPath, key) {
    // Extract IV from beginning
    // Decrypt file
    // Verify auth tag
  }
  
  deriveKey(password, salt) {
    // PBKDF2 with 100,000 iterations
    // Return 32-byte key
  }
}
```

**Key Points**:
- Use AES-256-GCM for authenticated encryption
- Store IV with encrypted data
- Use PBKDF2 for key derivation (if password-based)
- Support key rotation (re-encrypt old backups)

### 3. IPFS Integration (`ipfs/upload.js`)

```javascript
// Pseudo-code structure
class IPFSUploader {
  async uploadFile(filePath) {
    // Add file to IPFS
    // Get CID
    // Pin on both cluster nodes
    // Verify pin status
    // Return CID
  }
  
  async pinBackup(cid, replicationFactor = 2) {
    // Pin on IPFS cluster node 1
    // Pin on IPFS cluster node 2
    // Verify both pins succeeded
  }
  
  async verifyPin(cid) {
    // Check pin status on both nodes
    // Return true if pinned on both
  }
}
```

**Key Points**:
- Use IPFS HTTP API or cluster API
- Ensure replication factor of 2 (both nodes)
- Verify pin status after upload
- Handle network errors gracefully

### 4. Manifest Management (`manifest/manager.js`)

```javascript
// Pseudo-code structure
class BackupManifest {
  async addBackup(backupInfo) {
    // Load current manifest from IPFS
    // Add new backup entry
    // Update statistics
    // Upload updated manifest to IPFS
    // Store manifest CID in MongoDB (for quick access)
  }
  
  async getBackups(filters) {
    // Load manifest from IPFS or MongoDB
    // Filter by type, date range, etc.
    // Return matching backups
  }
  
  async removeBackup(cid) {
    // Remove from manifest
    // Update statistics
    // Upload updated manifest
  }
}
```

**Key Points**:
- Store manifest in both IPFS and MongoDB
- MongoDB for quick queries
- IPFS for immutable history
- Update after each backup operation

### 5. Retention Policy (`retention/cleanup.js`)

```javascript
// Pseudo-code structure
class RetentionManager {
  async cleanupOldBackups(retentionDays = 90) {
    // Load manifest
    // Find backups older than retention period
    // Unpin from IPFS cluster
    // Remove from manifest
    // Update manifest
    // Log cleanup statistics
  }
  
  async getBackupsToDelete(retentionDays) {
    // Query manifest for backups older than retention
    // Return list of CIDs to delete
  }
}
```

**Key Points**:
- Run after each backup (configurable)
- Unpin from both IPFS nodes
- Update manifest after cleanup
- Log what was deleted

### 6. Scheduler (`index.js`)

```javascript
// Pseudo-code structure
const cron = require('node-cron');

class BackupScheduler {
  start() {
    // Schedule full backup (weekly)
    cron.schedule('0 2 * * 0', async () => {
      await this.runFullBackup();
    });
    
    // Schedule incremental backup (daily)
    cron.schedule('0 2 * * *', async () => {
      await this.runIncrementalBackup();
    });
    
    // Schedule retention cleanup (daily, after backup)
    cron.schedule('30 2 * * *', async () => {
      await this.runRetentionCleanup();
    });
  }
  
  async runFullBackup() {
    // 1. Create backup
    // 2. Compress
    // 3. Encrypt
    // 4. Upload to IPFS
    // 5. Update manifest
    // 6. Log success
  }
}
```

## Docker Integration

### Dockerfile

```dockerfile
FROM node:18-alpine

# Install MongoDB tools
RUN apk add --no-cache mongodb-tools

# Install IPFS (if using CLI) or use HTTP client
# Option 1: Use IPFS HTTP client (Node.js)
# Option 2: Install go-ipfs binary

WORKDIR /app

COPY package*.json ./
RUN npm ci --production

COPY . .

# Create directories
RUN mkdir -p /tmp/backups /var/log/backups

# Run backup service
CMD ["node", "src/index.js"]
```

### Docker Compose Addition

```yaml
services:
  # ... existing MongoDB services ...
  
  mongodb-backup:
    build: ./ipfs-backup
    container_name: mongodb-backup
    restart: unless-stopped
    networks:
      - mongodb-network
    environment:
      - MONGODB_URI=${MONGODB_BACKUP_URI}
      - BACKUP_ENCRYPTION_KEY=${BACKUP_ENCRYPTION_KEY}
      - IPFS_NODE_1_URL=${IPFS_NODE_1_URL}
      - IPFS_NODE_2_URL=${IPFS_NODE_2_URL}
      - IPFS_CLUSTER_NODE_1=${IPFS_CLUSTER_NODE_1}
      - IPFS_CLUSTER_NODE_2=${IPFS_CLUSTER_NODE_2}
      - FULL_BACKUP_SCHEDULE=0 2 * * 0
      - INCREMENTAL_BACKUP_SCHEDULE=0 2 * * *
      - BACKUP_RETENTION_DAYS=90
    volumes:
      - ./tls-certs:/etc/mongo/ssl:ro
      - backup-temp:/tmp/backups
      - backup-logs:/var/log/backups
    depends_on:
      - mongodb-primary
      - mongodb-secondary-1
      - mongodb-secondary-2

volumes:
  backup-temp:
  backup-logs:
```

## Dependencies

### package.json

```json
{
  "name": "mongodb-ipfs-backup",
  "version": "1.0.0",
  "dependencies": {
    "mongodb": "^6.0.0",
    "ipfs-http-client": "^60.0.0",
    "node-cron": "^3.0.3",
    "tar": "^6.2.0",
    "zlib": "^1.0.5",
    "crypto": "^1.0.1"
  },
  "devDependencies": {
    "jest": "^29.0.0"
  }
}
```

## Configuration Management

### Environment Variables Priority

1. Environment variables (highest priority)
2. `.env` file
3. Default values

### Configuration Validation

- Validate all required environment variables on startup
- Fail fast if critical config is missing
- Log configuration on startup (mask sensitive values)

## Error Handling

### Retry Logic

- **MongoDB Connection**: Retry 3 times with exponential backoff
- **IPFS Upload**: Retry 3 times with exponential backoff
- **IPFS Pin**: Retry 5 times (critical operation)

### Error Recovery

- **Backup Failure**: Log error, send alert, continue with next schedule
- **IPFS Upload Failure**: Keep local backup, retry upload later
- **Pin Failure**: Retry pinning, alert if persistent
- **Manifest Update Failure**: Retry, log warning

## Logging Strategy

### Log Levels

- **INFO**: Normal operations (backup started, completed)
- **WARN**: Recoverable issues (retry, cleanup)
- **ERROR**: Failures requiring attention
- **DEBUG**: Detailed debugging information

### Log Format

```json
{
  "timestamp": "2024-01-15T02:00:00Z",
  "level": "INFO",
  "service": "mongodb-backup",
  "type": "full_backup",
  "status": "success",
  "duration": 45.2,
  "size": 5242880,
  "cid": "QmXxxx...",
  "message": "Full backup completed successfully"
}
```

## Testing Approach

### Unit Tests

- Encryption/decryption
- Manifest operations
- Retention logic
- Configuration loading

### Integration Tests

- Full backup workflow (mock IPFS)
- Incremental backup workflow
- IPFS upload (test environment)
- Retention cleanup

### End-to-End Tests

- Full backup → IPFS → Download → Decrypt → Verify
- Restore test (monthly)
- Point-in-time recovery test

## Monitoring & Metrics

### Metrics to Track

- Backup success rate
- Backup duration
- Backup size
- IPFS upload time
- IPFS pin success rate
- Retention cleanup statistics
- Storage usage

### Health Check Endpoint

```javascript
// Optional: HTTP health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    lastBackup: lastBackupTime,
    nextBackup: nextBackupTime,
    ipfsStatus: ipfsClusterStatus
  });
});
```

## Security Best Practices

1. **Key Management**:
   - Never log encryption keys
   - Use secrets manager in production
   - Rotate keys periodically

2. **Network Security**:
   - All connections over private network
   - TLS for MongoDB
   - IPFS cluster authentication

3. **File Permissions**:
   - Encrypted backups: 600 (owner read/write only)
   - Logs: 644 (readable by owner/group)

4. **Container Security**:
   - Run as non-root user
   - Minimal base image
   - No unnecessary packages

## Performance Considerations

Given small backup sizes (1-10MB):

1. **Compression**: May not be necessary for very small files (<1MB)
2. **Parallel Processing**: Can process multiple databases in parallel
3. **IPFS Upload**: Should be fast for small files
4. **Cleanup**: Batch operations for efficiency

## Recovery Tools

### CLI Restore Tool

```bash
# List backups
node restore/restore.js list [--type=full|incremental] [--since=YYYY-MM-DD]

# Download backup
node restore/restore.js download <CID> [--output=./backup.tar.gz.enc]

# Decrypt backup
node restore/restore.js decrypt <encrypted-file> [--output=./backup.tar.gz]

# Restore to MongoDB
node restore/restore.js restore <backup-dir> --uri="mongodb://..."

# Full restore workflow
node restore/restore.js restore-full <full-backup-cid> [--incremental=<cid>]
```

## Next Steps for Implementation

1. **Setup IPFS Cluster Access**: Verify connectivity and API endpoints
2. **Generate Encryption Key**: Create and securely store AES-256 key
3. **Create Project Structure**: Set up directory structure and files
4. **Implement Core Modules**: Start with MongoDB backup, then encryption, then IPFS
5. **Add Scheduling**: Implement cron-based scheduling
6. **Testing**: Unit tests, integration tests, end-to-end tests
7. **Documentation**: User guide, recovery procedures
8. **Deployment**: Add to docker-compose, configure environment
9. **Monitoring**: Set up logging and alerting
10. **Recovery Testing**: Test restore procedures
