# MongoDB High Availability (Replica Set) Setup Guide

This guide explains how to set up and use the High Availability (HA) MongoDB configuration with a 3-node replica set.

## Overview

The HA setup converts your single MongoDB instance into a **3-node replica set** that provides:

- **Automatic Failover**: If the primary node fails, a secondary automatically becomes primary
- **Data Redundancy**: Data is replicated across 3 nodes (3 copies)
- **Read Scaling**: Can read from secondary nodes to distribute load
- **Zero-Downtime Maintenance**: Can perform maintenance on one node while others continue serving

## Architecture

```
┌─────────────────┐
│  Primary Node   │ ← Handles all writes and primary reads
│ (mongodb-primary)│
└────────┬────────┘
         │ Replication
    ┌────┴────┐
    │         │
┌───▼───┐ ┌──▼────┐
│ Sec 1 │ │ Sec 2 │ ← Handle reads (optional) and provide redundancy
└───────┘ └───────┘
```

## Prerequisites

1. **Backup your existing data** (if migrating from single node)
2. **Regenerate TLS certificates** with replica set hostnames
3. **Sufficient resources**: 3x the resources of single node setup
4. **Docker and Docker Compose** installed

## Quick Start

### 1. Generate TLS Certificates and KeyFile

The TLS certificates must include all replica set member hostnames. Regenerate them:

```bash
./scripts/generate-tls-certs.sh
```

This will create certificates with Subject Alternative Names (SANs) for:
- `mongodb-primary`
- `mongodb-secondary-1`
- `mongodb-secondary-2`
- `localhost`

**Generate the keyFile** (required for replica set authentication when authorization is enabled):

```bash
./scripts/generate-keyfile.sh
```

The keyFile is used for inter-node authentication in the replica set. It must be the same on all nodes.

### 2. Configure Environment Variables

Edit your `.env` file:

```bash
# MongoDB credentials
MONGO_INITDB_ROOT_USERNAME=your_username
MONGO_INITDB_ROOT_PASSWORD=your_password
MONGO_PORT=27017

# Replica Set Configuration
REPLICA_SET_NAME=rs0

# Admin UI
ADMIN_UI_PORT=3000

# Optional: Web3 Auth
WEB3_AUTH_ENABLED=false
ADMIN_WALLETS=0xYourWalletAddress
SESSION_SECRET=your-secret-key
```

### 3. Start HA Services

Use the HA docker-compose file:

```bash
docker-compose -f docker-compose.ha.yaml up -d --build
```

This will:
1. Start 3 MongoDB nodes (primary + 2 secondaries)
2. Wait for all nodes to be healthy
3. Automatically initialize the replica set
4. Start the admin UI with replica set support

### 4. Verify Setup

Check replica set status:

```bash
docker exec -it mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status()"
```

You should see all 3 members with one PRIMARY and two SECONDARY nodes.

## Migration from Single Node

### Option 1: Fresh Start (Recommended for Development)

1. **Export your data** from the single node setup:
   ```bash
   # Use the admin UI or export tool
   # See EXPORT_IMPORT_GUIDE.md
   ```

2. **Stop the single node setup**:
   ```bash
   docker-compose down
   ```

3. **Start HA setup** (empty):
   ```bash
   docker-compose -f docker-compose.ha.yaml up -d
   ```

4. **Import your data** into the HA setup via admin UI

### Option 2: In-Place Migration (Advanced)

For production environments, you can convert an existing single node to a replica set:

1. **Backup your data**:
   ```bash
   docker exec mongo mongodump --tls \
     --tlsAllowInvalidCertificates \
     --tlsCAFile /etc/mongo/ssl/ca.crt \
     -u "$MONGO_INITDB_ROOT_USERNAME" \
     -p "$MONGO_INITDB_ROOT_PASSWORD" \
     --authenticationDatabase admin \
     --out /data/backup
   ```

2. **Stop single node**:
   ```bash
   docker-compose down
   ```

3. **Copy data to primary node volume**:
   ```bash
   # Copy db_data to db_data_primary
   cp -r db_data/* db_data_primary/
   ```

4. **Start HA setup**:
   ```bash
   docker-compose -f docker-compose.ha.yaml up -d
   ```

5. **The replica set will initialize and secondaries will sync from primary**

## Connection Strings

### For Applications (Replica Set)

```javascript
// Node.js example
const { MongoClient } = require('mongodb');

const client = new MongoClient(
  'mongodb://username:password@mongodb-primary:27017,mongodb-secondary-1:27017,mongodb-secondary-2:27017/?replicaSet=rs0&authSource=admin',
  {
    tls: true,
    tlsCAFile: './tls-certs/ca.crt',
    tlsAllowInvalidCertificates: true,
    readPreference: 'primaryPreferred' // Can read from secondaries
  }
);
```

### For mongosh (MongoDB Shell)

```bash
mongosh "mongodb://username:password@localhost:27017/?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

### Connection String Components

- **All members listed**: `mongodb-primary:27017,mongodb-secondary-1:27017,mongodb-secondary-2:27017`
- **Replica set name**: `replicaSet=rs0`
- **TLS enabled**: `tls=true`
- **Read preference** (optional): `readPreference=secondaryPreferred` (read from secondaries when possible)

## Monitoring and Maintenance

### Check Replica Set Status

```bash
docker exec -it mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status()"
```

### Check Which Node is Primary

```bash
docker exec -it mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.isMaster()"
```

### View Replication Lag

```bash
docker exec -it mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.printSlaveReplicationInfo()"
```

### Test Failover

To test automatic failover:

1. **Stop the primary node**:
   ```bash
   docker stop mongo-primary
   ```

2. **Wait 10-30 seconds** for election

3. **Check new primary**:
   ```bash
   docker exec -it mongo-secondary-1 mongosh --tls \
     --tlsAllowInvalidCertificates \
     --tlsCAFile /etc/mongo/ssl/ca.crt \
     -u "$MONGO_INITDB_ROOT_USERNAME" \
     -p "$MONGO_INITDB_ROOT_PASSWORD" \
     --authenticationDatabase admin \
     --eval "rs.isMaster()"
   ```

4. **Restart the old primary** (it will rejoin as secondary):
   ```bash
   docker start mongo-primary
   ```

## Troubleshooting

### Replica Set Not Initializing

**Problem**: `mongodb-init` container fails or replica set shows as "not initialized"

**Solutions**:
1. Check all MongoDB nodes are healthy:
   ```bash
   docker-compose -f docker-compose.ha.yaml ps
   ```

2. Check logs:
   ```bash
   docker-compose -f docker-compose.ha.yaml logs mongodb-init
   docker-compose -f docker-compose.ha.yaml logs mongodb-primary
   ```

3. Manually initialize if needed:
   ```bash
   docker exec -it mongo-primary mongosh --tls \
     --tlsAllowInvalidCertificates \
     --tlsCAFile /etc/mongo/ssl/ca.crt \
     -u "$MONGO_INITDB_ROOT_USERNAME" \
     -p "$MONGO_INITDB_ROOT_PASSWORD" \
     --authenticationDatabase admin \
     --eval "rs.initiate()"
   ```

### Secondary Nodes Not Syncing

**Problem**: Secondaries show as "STARTUP2" or "RECOVERING" for extended time

**Solutions**:
1. Check network connectivity between nodes
2. Verify TLS certificates are correct
3. Check disk space on secondary nodes
4. Review logs: `docker-compose -f docker-compose.ha.yaml logs mongodb-secondary-1`

### Connection Errors

**Problem**: Applications can't connect to replica set

**Solutions**:
1. Verify connection string includes `replicaSet=rs0`
2. Ensure all member hostnames are listed
3. Check TLS certificates are valid
4. Verify credentials are correct

### Primary Not Elected

**Problem**: No primary node after initialization

**Solutions**:
1. Ensure at least 2 nodes are healthy (need majority)
2. Check for network partitions
3. Verify all nodes can communicate
4. Check logs for election errors

## Data Volumes

The HA setup uses separate volumes for each node:

- `./db_data_primary` - Primary node data
- `./db_data_secondary1` - Secondary node 1 data
- `./db_data_secondary2` - Secondary node 2 data

**Important**: Each volume contains a full copy of the database. Ensure you have 3x the storage space.

## Performance Considerations

### Resource Requirements

- **Minimum**: 3x single node resources
- **Recommended**: 
  - CPU: 2-4 cores per node
  - RAM: 4-8GB per node
  - Storage: 3x your database size

### Read Preferences

Configure read preferences based on your needs:

- `primary` (default): All reads from primary (strong consistency)
- `primaryPreferred`: Read from primary, fallback to secondary
- `secondary`: Read only from secondaries (reduces primary load)
- `secondaryPreferred`: Prefer secondaries, fallback to primary
- `nearest`: Read from lowest latency node

### Write Concerns

Configure write concerns for durability:

- `w: 1` (default): Acknowledge after primary writes
- `w: "majority"`: Acknowledge after majority of nodes write (recommended for HA)
- `w: 2`: Acknowledge after 2 nodes write
- `j: true`: Wait for journal commit (durable writes)

Example:
```javascript
await collection.insertOne(doc, { 
  writeConcern: { w: 'majority', j: true } 
});
```

## Scaling Options

### Add More Secondaries

To add a 4th node (secondary-3):

1. Add service to `docker-compose.ha.yaml`:
   ```yaml
   mongodb-secondary-3:
     # ... (copy from secondary-2, update container_name and volume)
   ```

2. Add to replica set:
   ```bash
   docker exec -it mongo-primary mongosh --tls \
     --tlsAllowInvalidCertificates \
     --tlsCAFile /etc/mongo/ssl/ca.crt \
     -u "$MONGO_INITDB_ROOT_USERNAME" \
     -p "$MONGO_INITDB_ROOT_PASSWORD" \
     --authenticationDatabase admin \
     --eval "rs.add('mongodb-secondary-3:27017')"
   ```

### Use Arbiter (Lower Resource Option)

For environments with limited resources, use an arbiter instead of a full secondary:

- Arbiter participates in elections but doesn't store data
- Requires minimal resources
- Still provides automatic failover
- Only 2 data copies (less redundancy)

## Security Best Practices

1. **Use strong passwords** for MongoDB root user
2. **Rotate TLS certificates** before expiration
3. **Limit network exposure**: Only expose primary port externally
4. **Use firewall rules** to restrict access
5. **Enable audit logging** for production
6. **Keyfile authentication** is automatically configured for replica set members (required when authorization is enabled)

## Backup and Recovery

### Backup from Replica Set

Backup from a secondary to reduce primary load:

```bash
docker exec mongo-secondary-1 mongodump --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --out /data/backup
```

### Point-in-Time Recovery

Use Oplog for point-in-time recovery (requires oplog backup).

## Production Recommendations

1. **Use 5 nodes** instead of 3 for better fault tolerance
2. **Deploy across multiple availability zones** (if using cloud)
3. **Monitor replication lag** continuously
4. **Set up automated backups** from secondaries
5. **Use proper resource limits** in docker-compose
6. **Enable MongoDB monitoring** (MongoDB Atlas Monitoring or Ops Manager)
7. **Document runbooks** for common operations

## Additional Resources

- [MongoDB Replica Set Documentation](https://www.mongodb.com/docs/manual/replication/)
- [Replica Set Configuration](https://www.mongodb.com/docs/manual/reference/replica-configuration/)
- [Replica Set Read Preferences](https://www.mongodb.com/docs/manual/core/read-preference/)
- [Replica Set Write Concerns](https://www.mongodb.com/docs/manual/reference/write-concern/)

## Support

For issues or questions:
1. Check container logs: `docker-compose -f docker-compose.ha.yaml logs`
2. Review this documentation
3. Check MongoDB logs in containers
4. Verify network connectivity between nodes
