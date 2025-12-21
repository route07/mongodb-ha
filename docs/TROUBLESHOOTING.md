# Troubleshooting Guide

## Common Issues and Solutions

### Issue: "UserNotFound: Could not find user" Error

**Symptoms:**
- MongoDB containers start but authentication fails
- Error: `UserNotFound: Could not find user "username" for db "admin"`
- Primary node shows as unhealthy
- Secondary nodes don't start

**Cause:**
MongoDB only creates the root user automatically when the database is first initialized (when `/data/db` is empty). If the data directory already exists from a previous run, MongoDB won't create the user again, but will still require authentication.

**Solution 1: Fresh Start (Recommended for Development)**

If you don't need to preserve existing data:

```bash
# Stop all containers
docker-compose down

# Remove all data directories
rm -rf db_data_primary/
rm -rf db_data_secondary1/
rm -rf db_data_secondary2/

# Start fresh
docker-compose up -d
```

**Solution 2: Keep Data and Create User**

If you need to preserve data, the `mongodb-init-user` container will automatically create the user if it doesn't exist. However, if MongoDB requires authentication but the user doesn't exist, you may need to:

1. **Temporarily disable authentication** (if possible):
   ```bash
   # Stop containers
   docker-compose down
   
   # Edit docker-compose.yaml temporarily to remove --keyFile and auth
   # Start MongoDB
   docker-compose up -d mongodb-primary
   
   # Create user manually
   docker exec -it mongo-primary mongosh --tls \
     --tlsAllowInvalidCertificates \
     --tlsCAFile /etc/mongo/ssl/ca.crt \
     --eval "
       db.getSiblingDB('admin').createUser({
         user: 'YOUR_USERNAME',
         pwd: 'YOUR_PASSWORD',
         roles: [{ role: 'root', db: 'admin' }]
       })
     "
   
   # Restore docker-compose.yaml and restart
   docker-compose down
   docker-compose up -d
   ```

2. **Use the init-user script manually**:
   ```bash
   # Ensure MongoDB is running
   docker-compose up -d mongodb-primary
   
   # Run the init-user script
   docker run --rm --network ha-mongodb_db-network \
     -v $(pwd)/tls-certs:/etc/mongo/ssl:ro \
     -v $(pwd)/scripts:/scripts:ro \
     -e MONGO_INITDB_ROOT_USERNAME=YOUR_USERNAME \
     -e MONGO_INITDB_ROOT_PASSWORD=YOUR_PASSWORD \
     mongo:7.0 \
     bash /scripts/init-user.sh mongodb-primary 27017
   ```

**Solution 3: Check Environment Variables**

Ensure your `.env` file has the correct values:

```bash
MONGO_INITDB_ROOT_USERNAME=your_username
MONGO_INITDB_ROOT_PASSWORD=your_password
```

Then restart:

```bash
docker-compose down
docker-compose up -d
```

### Issue: Primary Node Unhealthy

**Symptoms:**
- Primary container keeps restarting
- Healthcheck fails
- Secondary nodes don't start

**Solutions:**

1. **Check logs**:
   ```bash
   docker-compose logs mongodb-primary
   ```

2. **Check if MongoDB process is running**:
   ```bash
   docker exec mongo-primary ps aux | grep mongod
   ```

3. **Check keyfile permissions**:
   ```bash
   docker exec mongo-primary ls -la /data/keyfile
   # Should show: -rw------- 1 999 999
   ```

4. **Verify TLS certificates**:
   ```bash
   ls -la tls-certs/
   # Should have: ca.crt, server.pem, keyfile
   ```

5. **Check if user exists**:
   ```bash
   docker exec mongo-primary mongosh --tls \
     --tlsAllowInvalidCertificates \
     --tlsCAFile /etc/mongo/ssl/ca.crt \
     --eval "db.getSiblingDB('admin').getUsers()"
   ```

### Issue: Replica Set Not Initializing

**Symptoms:**
- All nodes are healthy but replica set shows as "not initialized"
- `mongodb-init` container fails

**Solutions:**

1. **Check init logs**:
   ```bash
   docker-compose logs mongodb-init
   ```

2. **Manually initialize replica set**:
   ```bash
   docker exec -it mongo-primary mongosh --tls \
     --tlsAllowInvalidCertificates \
     --tlsCAFile /etc/mongo/ssl/ca.crt \
     -u "$MONGO_INITDB_ROOT_USERNAME" \
     -p "$MONGO_INITDB_ROOT_PASSWORD" \
     --authenticationDatabase admin \
     --eval "
       rs.initiate({
         _id: 'rs0',
         members: [
           { _id: 0, host: 'mongodb-primary:27017', priority: 2 },
           { _id: 1, host: 'mongodb-secondary-1:27017', priority: 1 },
           { _id: 2, host: 'mongodb-secondary-2:27017', priority: 1 }
         ]
       })
     "
   ```

3. **Check network connectivity**:
   ```bash
   docker exec mongo-primary ping -c 2 mongodb-secondary-1
   docker exec mongo-primary ping -c 2 mongodb-secondary-2
   ```

### Issue: Keyfile Permission Errors

**Symptoms:**
- Error: "Unable to acquire security key[s]"
- Error: "error opening file: /etc/mongo/ssl/keyfile: bad file"

**Solutions:**

1. **Regenerate keyfile**:
   ```bash
   ./scripts/generate-keyfile.sh
   ```

2. **Check keyfile exists and has correct format**:
   ```bash
   # Should be 6-1024 characters, no trailing newline
   wc -c tls-certs/keyfile
   tail -c 1 tls-certs/keyfile | od -An -tx1
   # Should not show 0a (newline)
   ```

3. **Fix keyfile** (remove trailing newline):
   ```bash
   tr -d '\n' < tls-certs/keyfile > tls-certs/keyfile.tmp
   mv tls-certs/keyfile.tmp tls-certs/keyfile
   chmod 600 tls-certs/keyfile
   ```

### Issue: TLS Certificate Errors

**Symptoms:**
- Connection errors related to TLS
- Certificate validation failures

**Solutions:**

1. **Regenerate certificates**:
   ```bash
   ./scripts/generate-tls-certs.sh
   ```

2. **Verify certificates include replica set hostnames**:
   ```bash
   openssl x509 -in tls-certs/server.crt -text -noout | grep -A 5 "Subject Alternative Name"
   # Should show: mongodb-primary, mongodb-secondary-1, mongodb-secondary-2
   ```

3. **Check certificate expiration**:
   ```bash
   openssl x509 -in tls-certs/server.crt -noout -dates
   ```

### Issue: Secondary Nodes Not Syncing

**Symptoms:**
- Secondaries show as "STARTUP2" or "RECOVERING" for extended time
- Replication lag increases

**Solutions:**

1. **Check secondary logs**:
   ```bash
   docker-compose logs mongodb-secondary-1
   docker-compose logs mongodb-secondary-2
   ```

2. **Check disk space**:
   ```bash
   df -h
   ```

3. **Check network connectivity between nodes**:
   ```bash
   docker exec mongo-primary ping -c 2 mongodb-secondary-1
   ```

4. **Verify keyfile is identical on all nodes**:
   ```bash
   md5sum tls-certs/keyfile
   # Should be the same on all nodes
   ```

### Issue: mongo-admin Can't Connect

**Symptoms:**
- Admin UI shows "Connection Error"
- Can't resolve "mongodb-primary" hostname

**Solutions:**

1. **Check mongo-admin logs**:
   ```bash
   docker-compose logs mongo-admin
   ```

2. **Verify network**:
   ```bash
   docker network ls | grep ha-mongodb
   docker network inspect ha-mongodb_db-network
   ```

3. **Check environment variables**:
   ```bash
   docker exec mongo-admin env | grep MONGO
   ```

4. **Test connection from mongo-admin container**:
   ```bash
   docker exec mongo-admin ping -c 2 mongodb-primary
   ```

## General Debugging Commands

### Check All Container Status
```bash
docker-compose ps
```

### View All Logs
```bash
docker-compose logs
```

### View Logs for Specific Service
```bash
docker-compose logs mongodb-primary
docker-compose logs mongodb-init-user
docker-compose logs mongodb-init
```

### Connect to MongoDB Shell
```bash
docker exec -it mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin
```

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

### Restart Everything
```bash
docker-compose down
docker-compose up -d
```

### Complete Reset (⚠️ Deletes All Data)
```bash
docker-compose down -v
rm -rf db_data_primary/ db_data_secondary1/ db_data_secondary2/
docker-compose up -d
```

## Getting Help

If you continue to experience issues:

1. Collect logs: `docker-compose logs > logs.txt`
2. Check container status: `docker-compose ps`
3. Verify environment variables in `.env` file
4. Check MongoDB version: `docker exec mongo-primary mongod --version`
5. Review this troubleshooting guide

For more information, see:
- [HA Setup Guide](./HA_SETUP.md)
- [TLS Setup Guide](./TLS_SETUP.md)
