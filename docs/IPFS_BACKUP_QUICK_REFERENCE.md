# IPFS Backup Quick Reference

## Strategy Summary

### Backup Configuration

| Setting | Value |
|---------|-------|
| **Full Backup** | Weekly (Sunday 2 AM) |
| **Incremental Backup** | Daily (2 AM) |
| **Retention** | 90 days |
| **Encryption** | AES-256-GCM |
| **IPFS Replication** | 2 nodes (both store each backup) |
| **Backup Source** | MongoDB Secondary (read preference) |
| **Format** | BSON (mongodump) → gzip → encrypted |

### Architecture Components

```
MongoDB Secondary → Backup Service → IPFS Cluster (2 nodes)
     ↓                    ↓                    ↓
  Read data          Encrypt & Compress    Pin on both nodes
```

### Backup Workflow

1. **Connect** to MongoDB secondary
2. **Dump** all databases (mongodump)
3. **Compress** (gzip)
4. **Encrypt** (AES-256-GCM)
5. **Upload** to IPFS → Get CID
6. **Pin** on both IPFS nodes
7. **Update** manifest
8. **Cleanup** old backups (>90 days)

### File Naming

- **Full Backup**: `full_backup_2024-01-14_020000.tar.gz.enc`
- **Incremental**: `incremental_backup_2024-01-15_020000.tar.gz.enc`
- **Manifest**: Stored in IPFS + MongoDB

### Key Decisions

✅ **BSON Format**: Native MongoDB format, efficient for restore  
✅ **AES-256-GCM**: Authenticated encryption with IV  
✅ **Secondary Source**: No impact on primary performance  
✅ **IPFS Cluster**: Distributed pinning with replication factor 2  
✅ **Manifest in MongoDB**: Quick queries, IPFS for immutability  

### Environment Variables Required

```bash
# MongoDB
MONGODB_URI=mongodb://user:pass@secondary:27018/?replicaSet=rs0&tls=true&readPreference=secondary

# Encryption
BACKUP_ENCRYPTION_KEY=<256-bit-key-base64>

# IPFS
IPFS_NODE_1_URL=http://ipfs-node-1:5001
IPFS_NODE_2_URL=http://ipfs-node-2:5001
IPFS_CLUSTER_NODE_1=http://ipfs-node-1:9094
IPFS_CLUSTER_NODE_2=http://ipfs-node-2:9094

# Schedule
FULL_BACKUP_SCHEDULE=0 2 * * 0
INCREMENTAL_BACKUP_SCHEDULE=0 2 * * *
BACKUP_RETENTION_DAYS=90
```

### Recovery Commands

```bash
# List backups
node restore.js list

# Download from IPFS
node restore.js download <CID>

# Decrypt
node restore.js decrypt <file.enc> <output.tar.gz>

# Restore
mongorestore --uri="mongodb://..." <backup-dir>
```

### Monitoring Checklist

- [ ] Backup success rate > 99%
- [ ] IPFS pin status verified on both nodes
- [ ] No backups older than 26 hours
- [ ] Retention cleanup running successfully
- [ ] Storage usage < 80% capacity
- [ ] Encryption/decryption tests passing

### Security Checklist

- [ ] Encryption key stored securely (not in git)
- [ ] All connections over private network
- [ ] TLS for MongoDB connections
- [ ] IPFS cluster authentication configured
- [ ] Backup service runs as non-root
- [ ] File permissions: 600 for encrypted backups

### Implementation Phases

**Phase 1: Core Backup**
- MongoDB dump
- Compression
- Encryption
- Basic IPFS upload

**Phase 2: Scheduling & Automation**
- Cron scheduling
- Manifest management
- Retention cleanup

**Phase 3: Monitoring & Recovery**
- Logging & alerts
- Restore tools
- Health checks

**Phase 4: Testing & Hardening**
- Unit tests
- Integration tests
- Recovery testing
- Security audit

### Estimated Timeline

- **Phase 1**: 2-3 days
- **Phase 2**: 2-3 days
- **Phase 3**: 1-2 days
- **Phase 4**: 2-3 days
- **Total**: ~1-2 weeks

### Questions to Resolve Before Implementation

1. **IPFS API**: HTTP API, Cluster API, or CLI?
2. **Key Storage**: Environment variable or secrets manager?
3. **Notification**: Email, Slack, or other?
4. **Backup Verification**: Automated restore tests? Frequency?
5. **Local Storage**: Keep backups locally before IPFS? (For faster recovery)

### Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Backup failure | Retry logic, alerts, manual trigger |
| IPFS pin failure | Verify pin status, retry, alert |
| Encryption key loss | Secure backup of key, key rotation plan |
| IPFS cluster down | Local backup retention, alternative storage |
| Restore failure | Regular restore tests, documentation |

### Success Criteria

✅ Backups run automatically on schedule  
✅ All backups encrypted and pinned on both IPFS nodes  
✅ Retention policy automatically removes old backups  
✅ Restore process tested and documented  
✅ Monitoring and alerts configured  
✅ Recovery time < 30 minutes for full restore  
