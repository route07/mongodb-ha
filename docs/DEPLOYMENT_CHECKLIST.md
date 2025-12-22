# Remote Server Deployment Checklist

Quick checklist for deploying MongoDB HA Replica Set on remote server.

## Pre-Deployment

- [ ] Remote server has Docker and Docker Compose installed
- [ ] At least 4GB RAM available (8GB+ recommended)
- [ ] At least 20GB free disk space
- [ ] Ports 27017 and 3000 are accessible (or configure firewall)
- [ ] SSH access to remote server

## Deployment Steps

### 1. Transfer Files
- [ ] Files transferred to remote server (git clone, scp, or rsync)
- [ ] All scripts are executable: `chmod +x scripts/*.sh`

### 2. Configuration
- [ ] `.env` file created from `.env.example`
- [ ] `MONGO_INITDB_ROOT_USERNAME` set
- [ ] `MONGO_INITDB_ROOT_PASSWORD` set (strong password)
- [ ] `REPLICA_SET_NAME` set (default: rs0)
- [ ] Other environment variables configured as needed

### 3. Generate Certificates
- [ ] TLS certificates generated: `./scripts/generate-tls-certs.sh`
- [ ] KeyFile generated: `./scripts/generate-keyfile.sh`
- [ ] Certificates exist in `tls-certs/` directory

### 4. Start Services
- [ ] Services started: `docker-compose up -d`
- [ ] Waited 60-90 seconds for initialization
- [ ] All containers running: `docker-compose ps`

### 5. Verify Setup
- [ ] Primary node is healthy
- [ ] Secondary nodes are healthy
- [ ] Replica set initialized (check with `rs.status()`)
- [ ] mongo-admin connected successfully
- [ ] Admin UI accessible at `http://SERVER_IP:3000`
- [ ] Cluster status shows 3 nodes in Admin UI

### 6. Security (Optional but Recommended)
- [ ] Firewall configured (if applicable)
- [ ] keyFile re-enabled in docker-compose.yaml (after user exists)
- [ ] MongoDB port restricted (or use SSH tunnel)
- [ ] Strong passwords in use

## Post-Deployment

- [ ] Tested MongoDB connection
- [ ] Tested Admin UI functionality
- [ ] Verified replica set failover (optional)
- [ ] Backup strategy planned
- [ ] Monitoring configured (optional)

## Troubleshooting

If something doesn't work:

1. **User Not Found**: Run `./scripts/fix-user-quick.sh`
2. **Replica Set Not Initialized**: Run `./scripts/init-replica-set-manual.sh`
3. **Can't Connect**: Check firewall, verify containers are running
4. **Check Logs**: `docker-compose logs`

## Quick Commands

```bash
# Status
docker-compose ps

# Logs
docker-compose logs -f

# Restart
docker-compose restart

# Stop
docker-compose down

# Start
docker-compose up -d
```

## Success Indicators

✅ All containers show "Up" and "healthy"  
✅ Replica set shows PRIMARY + 2 SECONDARY  
✅ Admin UI loads and shows cluster status  
✅ No authentication errors in logs  
✅ Oplog warnings are gone (after initialization)
