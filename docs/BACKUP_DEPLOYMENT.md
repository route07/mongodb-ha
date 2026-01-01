# Backup Service Deployment

## Quick Answer

**Yes, you can run the backup service separately without modifying your existing docker-compose.yaml!**

However, you need to use both compose files together so they share the same Docker network.

## Deployment Options

### Option 1: Use Both Compose Files Together (Recommended)

This ensures the backup service is on the same network as MongoDB:

```bash
# Start everything together
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml up -d mongodb-backup

# Or start all services (MongoDB + Backup)
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml up -d
```

**Why this works:**
- Both files reference the same `db-network`
- Docker Compose combines them into one project
- Services can communicate via service names (e.g., `mongodb-secondary-1`)

### Option 2: Add to Existing docker-compose.yaml

If you prefer a single file, you can add the backup service directly to your existing `docker-compose.yaml`:

1. Copy the `mongodb-backup` service from `docker-compose.backup.yaml`
2. Copy the volumes section
3. Add to your existing `docker-compose.yaml`

Then just run:
```bash
docker-compose up -d mongodb-backup
```

### Option 3: Use External Network (Advanced)

If your MongoDB is already running and you want to connect to an existing network:

1. Find your MongoDB network:
   ```bash
   docker network ls
   docker inspect <mongodb-container> | grep NetworkMode
   ```

2. Update `docker-compose.backup.yaml` to use external network:
   ```yaml
   networks:
     db-network:
       external: true
       name: <your-network-name>
   ```

3. Run backup service:
   ```bash
   docker-compose -f docker-compose.backup.yaml up -d
   ```

## Recommended Approach

**Use Option 1** - it's the simplest and ensures everything works correctly:

```bash
# 1. Make sure MongoDB is running
docker-compose ps

# 2. Start backup service (using both compose files)
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml up -d mongodb-backup

# 3. Verify it's running
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml ps mongodb-backup

# 4. Check logs
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml logs mongodb-backup
```

## Important Notes

1. **Network Sharing**: The backup service MUST be on the same Docker network as MongoDB to connect via service names (`mongodb-secondary-1`, etc.)

2. **TLS Certificates**: The backup service mounts `./tls-certs` - make sure this path exists and contains your certificates

3. **Environment Variables**: Add backup configuration to your `.env` file (see setup guide)

4. **No MongoDB Restart Needed**: Your existing MongoDB cluster continues running - no changes needed!

## Verification

After starting the backup service, verify connectivity:

```bash
# Check backup service can reach MongoDB
docker exec mongodb-backup mongosh "${MONGODB_URI}" --eval "db.adminCommand('ping')"

# Check IPFS connectivity
docker exec mongodb-backup node -e "
  const {create} = require('ipfs-http-client');
  create({url: process.env.IPFS_NODE_1_URL}).id().then(console.log);
"
```

## Stopping/Removing

To stop just the backup service:
```bash
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml stop mongodb-backup
```

To remove (keeps volumes):
```bash
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml rm mongodb-backup
```

To remove with volumes:
```bash
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml down -v mongodb-backup
```

## Troubleshooting

### "Network not found" error

If you get a network error, make sure to use both compose files together:
```bash
docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml up -d
```

### "Cannot connect to MongoDB" error

1. Verify MongoDB is running: `docker-compose ps`
2. Check network: `docker network inspect <project>_db-network`
3. Test connection from backup container: `docker exec mongodb-backup ping mongodb-secondary-1`

### Service name resolution

The backup service connects to MongoDB using Docker service names:
- `mongodb-secondary-1:27017`
- `mongodb-secondary-2:27017`

These only work if services are on the same Docker network (which Option 1 ensures).
