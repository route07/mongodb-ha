# IPFS Backup Strategy for HA MongoDB

## Overview

This document outlines the strategy for backing up the HA MongoDB replica set to IPFS with encryption, scheduled backups, and automated retention management.

## Requirements Summary

- **Backup Scope**: All databases
- **Full Backup Frequency**: Weekly
- **Incremental Backup Frequency**: Daily
- **Retention Period**: 3 months (90 days)
- **Encryption**: Required (AES-256)
- **IPFS Cluster**: 2 nodes, replication factor 2 (both nodes store each backup)
- **Network**: Direct private network access to IPFS cluster
- **Expected Size**: 1MB - 10MB per backup
- **RTO**: Fast recovery

## Architecture

```
┌─────────────────────────────────────────┐
│  MongoDB HA Cluster                     │
│  ┌──────────┐  ┌──────────┐  ┌──────┐  │
│  │ Primary  │  │Secondary1│  │Sec 2 │  │
│  │ :27017   │  │ :27018   │  │:27019│  │
│  └────┬─────┘  └────┬─────┘  └──┬───┘  │
└───────┼─────────────┼───────────┼──────┘
        │             │           │
        └─────────────┴───────────┘
                      │
        ┌─────────────▼─────────────┐
        │  Backup Service Container │
        │  - Connects to secondary  │
        │  - mongodump (BSON)       │
        │  - Compression (gzip)    │
        │  - Encryption (AES-256)   │
        │  - IPFS upload            │
        │  - Retention management   │
        └─────────────┬─────────────┘
                      │
        ┌─────────────▼─────────────┐
        │  IPFS Private Cluster      │
        │  ┌──────────┐  ┌────────┐ │
        │  │ Node 1   │  │ Node 2 │ │
        │  │ (Pin)    │  │ (Pin)  │ │
        │  └──────────┘  └────────┘ │
        │  Replication Factor: 2    │
        └───────────────────────────┘
```

## Backup Types

### 1. Full Backup (Weekly)
- **Schedule**: Every Sunday at 2:00 AM (configurable)
- **Method**: `mongodump` - exports all databases in BSON format
- **Output**: Compressed, encrypted archive
- **Naming**: `full_backup_YYYY-MM-DD_HHMMSS.tar.gz.enc`

### 2. Incremental Backup (Daily)
- **Schedule**: Every day at 2:00 AM (configurable)
- **Method**: Oplog-based backup using `mongodump --oplog`
- **Output**: Compressed, encrypted oplog archive
- **Naming**: `incremental_backup_YYYY-MM-DD_HHMMSS.tar.gz.enc`
- **Note**: Requires a full backup to restore from

### 3. Backup Manifest
- **Purpose**: Track all backups, their CIDs, timestamps, and metadata
- **Storage**: Stored in IPFS and also in MongoDB (for quick access)
- **Format**: JSON with backup metadata
- **Updated**: After each successful backup

## Implementation Components

### 1. Backup Service Container

**Location**: `ipfs-backup/` directory

**Structure**:
```
ipfs-backup/
├── Dockerfile
├── package.json
├── .env.example
├── src/
│   ├── index.js              # Main entry point
│   ├── backup.js             # Backup orchestration
│   ├── mongodb.js            # MongoDB connection & dump
│   ├── encryption.js         # AES-256 encryption/decryption
│   ├── ipfs.js               # IPFS upload & pinning
│   ├── retention.js          # Cleanup old backups
│   ├── manifest.js           # Manifest management
│   └── scheduler.js          # Cron scheduling
├── config/
│   └── backup-config.json    # Backup configuration
└── README.md
```

### 2. Backup Workflow

```
1. Connect to MongoDB Secondary (read preference)
   ↓
2. Execute mongodump (full or incremental)
   ↓
3. Compress backup (tar.gz)
   ↓
4. Encrypt backup (AES-256-GCM)
   ↓
5. Upload to IPFS → Get CID
   ↓
6. Pin backup on both IPFS nodes (replication factor 2)
   ↓
7. Update manifest (store CID, timestamp, type, metadata)
   ↓
8. Store manifest CID in MongoDB (for quick access)
   ↓
9. Run retention policy (delete backups older than 90 days)
   ↓
10. Cleanup local temp files
    ↓
11. Log success/failure
```

### 3. Encryption Strategy

**Algorithm**: AES-256-GCM (authenticated encryption)
- **Key Management**: 
  - Encryption key stored in environment variable or secrets manager
  - Key derivation: PBKDF2 with 100,000 iterations
  - IV: Random 12 bytes (stored with encrypted file)
- **File Format**: `[IV (12 bytes)][Encrypted Data][Auth Tag (16 bytes)]`
- **Key Storage**: 
  - Primary: Environment variable `BACKUP_ENCRYPTION_KEY`
  - Backup: Store encrypted key in secure location (separate from backups)

### 4. IPFS Integration

**IPFS Client**: `ipfs-http-client` (Node.js) or `go-ipfs` CLI

**Configuration**:
- **IPFS Gateway**: Private cluster gateway endpoints
- **Pinning**: Use `ipfs-cluster` for distributed pinning
- **Replication**: Ensure both nodes pin each backup
- **Verification**: Verify pin status after upload

**IPFS Cluster Setup**:
```javascript
// Example IPFS cluster configuration
const ipfsCluster = {
  nodes: [
    { host: 'ipfs-node-1.internal', port: 9094 },
    { host: 'ipfs-node-2.internal', port: 9094 }
  ],
  replicationFactor: 2,
  timeout: 30000
};
```

### 5. Retention Policy

**Rules**:
- Keep all full backups for 90 days
- Keep incremental backups for 90 days (or until next full backup if older)
- Delete backups older than 90 days from IPFS (unpin)
- Update manifest after cleanup

**Implementation**:
- Run retention check after each backup
- Query manifest for backups older than retention period
- Unpin from IPFS cluster
- Update manifest

### 6. Manifest Structure

```json
{
  "version": "1.0",
  "lastUpdated": "2024-01-15T10:30:00Z",
  "backups": [
    {
      "type": "full",
      "cid": "QmXxxx...",
      "timestamp": "2024-01-14T02:00:00Z",
      "size": 5242880,
      "encrypted": true,
      "databases": ["db1", "db2", "db3"],
      "mongodbVersion": "7.0",
      "replicaSet": "rs0"
    },
    {
      "type": "incremental",
      "cid": "QmYyyy...",
      "timestamp": "2024-01-15T02:00:00Z",
      "size": 1048576,
      "encrypted": true,
      "baseBackup": "QmXxxx...",
      "oplogStart": "2024-01-14T02:00:00Z",
      "oplogEnd": "2024-01-15T02:00:00Z"
    }
  ],
  "statistics": {
    "totalBackups": 45,
    "totalSize": 52428800,
    "oldestBackup": "2024-01-01T02:00:00Z",
    "newestBackup": "2024-01-15T02:00:00Z"
  }
}
```

## Configuration

### Environment Variables

```bash
# MongoDB Connection
MONGODB_URI=mongodb://username:password@mongodb-secondary-1:27018/?replicaSet=rs0&tls=true&tlsCAFile=/etc/mongo/ssl/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin&readPreference=secondary

# Encryption
BACKUP_ENCRYPTION_KEY=your-256-bit-key-here-base64-encoded
ENCRYPTION_KEY_DERIVATION_ITERATIONS=100000

# IPFS Configuration
IPFS_NODE_1_URL=http://ipfs-node-1.internal:5001
IPFS_NODE_2_URL=http://ipfs-node-2.internal:5001
IPFS_CLUSTER_NODE_1=http://ipfs-node-1.internal:9094
IPFS_CLUSTER_NODE_2=http://ipfs-node-2.internal:9094
IPFS_REPLICATION_FACTOR=2

# Backup Schedule
FULL_BACKUP_SCHEDULE=0 2 * * 0  # Sunday 2 AM
INCREMENTAL_BACKUP_SCHEDULE=0 2 * * *  # Daily 2 AM

# Retention
BACKUP_RETENTION_DAYS=90

# Storage
BACKUP_TEMP_DIR=/tmp/mongodb-backups
BACKUP_LOG_DIR=/var/log/backups
```

### Backup Configuration File

```json
{
  "backup": {
    "source": {
      "type": "secondary",
      "readPreference": "secondary"
    },
    "full": {
      "enabled": true,
      "schedule": "0 2 * * 0",
      "databases": "all",
      "compression": "gzip",
      "compressionLevel": 6
    },
    "incremental": {
      "enabled": true,
      "schedule": "0 2 * * *",
      "oplog": true
    },
    "encryption": {
      "algorithm": "aes-256-gcm",
      "keyDerivation": "pbkdf2",
      "iterations": 100000
    },
    "ipfs": {
      "replicationFactor": 2,
      "pinTimeout": 30000,
      "verifyAfterUpload": true
    },
    "retention": {
      "days": 90,
      "cleanupAfterBackup": true
    }
  }
}
```

## Recovery Process

### Full Backup Recovery

```bash
# 1. List available backups
node restore.js list

# 2. Download backup from IPFS
node restore.js download <CID>

# 3. Decrypt backup
node restore.js decrypt <encrypted-file> <output-dir>

# 4. Extract backup
tar -xzf <backup-file> -C <output-dir>

# 5. Restore to MongoDB
mongorestore --uri="mongodb://..." <backup-dir>
```

### Point-in-Time Recovery

```bash
# 1. Restore full backup
mongorestore --uri="..." <full-backup-dir>

# 2. Apply incremental backups up to target time
mongorestore --uri="..." --oplogReplay <incremental-backup-dir>
```

## Monitoring & Alerts

### Health Checks

- **Backup Success Rate**: Track successful vs failed backups
- **IPFS Pin Status**: Verify backups are pinned on both nodes
- **Storage Usage**: Monitor IPFS cluster storage
- **Backup Age**: Alert if no backup in last 25 hours (daily check)
- **Encryption Verification**: Test decrypt random backup periodically

### Logging

- **Backup Start/End**: Timestamp, type, duration
- **IPFS Upload**: CID, size, pin status
- **Retention Cleanup**: Deleted backups, freed space
- **Errors**: Detailed error logs with stack traces

### Alerts

- Backup failure
- IPFS pin failure
- Retention cleanup failure
- Storage threshold exceeded (>80% capacity)
- Backup age > 26 hours (missed daily backup)

## Security Considerations

1. **Encryption Key Management**:
   - Never commit keys to git
   - Use secrets manager in production
   - Rotate keys periodically (requires re-encryption of old backups)

2. **Network Security**:
   - All connections over private network
   - TLS for MongoDB connections
   - IPFS cluster authentication (if supported)

3. **Access Control**:
   - Backup service runs with minimal privileges
   - Read-only access to MongoDB (secondary)
   - IPFS write access only for backup service

4. **Backup Verification**:
   - Periodic restore tests
   - Verify encryption/decryption
   - Verify IPFS integrity (CID verification)

## Performance Optimization

Given small backup sizes (1-10MB):

1. **Parallel Processing**:
   - Can process multiple databases in parallel
   - Upload to IPFS while compressing next backup

2. **Compression**:
   - Use gzip level 6 (good balance)
   - For very small backups, compression overhead may not be worth it

3. **IPFS Upload**:
   - Direct upload to cluster nodes
   - Verify pin status asynchronously

4. **Cleanup**:
   - Run retention cleanup asynchronously
   - Batch unpin operations

## Testing Strategy

1. **Unit Tests**:
   - Encryption/decryption
   - Manifest management
   - Retention logic

2. **Integration Tests**:
   - Full backup → IPFS → Download → Decrypt → Verify
   - Incremental backup workflow
   - Retention cleanup

3. **Recovery Tests**:
   - Monthly restore test from IPFS
   - Point-in-time recovery test
   - Verify data integrity

## Deployment Considerations

1. **Docker Compose Integration**:
   - Add backup service to `docker-compose.ha.yaml`
   - Share network with MongoDB containers
   - Mount TLS certificates

2. **Resource Requirements**:
   - CPU: Minimal (backups are small)
   - Memory: 512MB should be sufficient
   - Disk: Temporary storage for backups (~100MB)

3. **Dependencies**:
   - MongoDB tools (mongodump, mongorestore)
   - IPFS client (ipfs-http-client or go-ipfs)
   - Node.js runtime

## Next Steps

1. **Review & Approve Strategy**: Confirm approach meets requirements
2. **IPFS Cluster Setup**: Ensure IPFS cluster is configured and accessible
3. **Encryption Key Generation**: Generate and securely store encryption key
4. **Implementation**: Build backup service according to this strategy
5. **Testing**: Test backup and restore workflows
6. **Deployment**: Deploy to production with monitoring
7. **Documentation**: Create recovery runbooks

## Questions & Decisions

- **IPFS Cluster API**: Which API will be used? (HTTP API, Cluster API, or CLI)
- **Key Rotation**: How often should encryption keys be rotated?
- **Backup Verification**: Automated restore tests? How frequently?
- **Notification Channel**: Where should alerts be sent? (Email, Slack, etc.)
- **Backup Location**: Should backups be stored locally before IPFS upload? (For faster recovery)
