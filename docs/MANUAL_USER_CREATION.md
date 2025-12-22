# Manual User Creation on Remote Server

Step-by-step guide to manually create the MongoDB user on remote server.

## Step 1: Check Current State

```bash
# On remote server
cd ~/ha-mongodb

# Check if containers are running
docker-compose ps

# Check if primary is running
docker ps | grep mongo-primary
```

## Step 2: Verify MongoDB is Accessible

```bash
# Test if you can connect without authentication
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "db.adminCommand('ping')"
```

**Expected**: Should return `{ ok: 1 }`

If this fails, MongoDB might require authentication. See troubleshooting below.

## Step 3: Check Your .env File

```bash
# Verify credentials are set
cat .env | grep MONGO_INITDB

# Should show:
# MONGO_INITDB_ROOT_USERNAME=rbdbuser
# MONGO_INITDB_ROOT_PASSWORD=your_password
```

## Step 4: Create User Manually

```bash
# Source the environment variables
source .env

# Create the user (without authentication)
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "
    db.getSiblingDB('admin').createUser({
      user: '$MONGO_INITDB_ROOT_USERNAME',
      pwd: '$MONGO_INITDB_ROOT_PASSWORD',
      roles: [{ role: 'root', db: 'admin' }]
    })
  "
```

**Expected Output**: `{ ok: 1 }`

## Step 5: Verify User Works

```bash
# Test authentication
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"
```

**Expected**: `{ ok: 1 }`

## Step 6: Restart Services

```bash
# Restart to ensure everything picks up the user
docker-compose restart

# Wait a moment
sleep 10

# Check status
docker-compose ps
```

## Step 7: Initialize Replica Set (if not done)

```bash
# Check if replica set is initialized
source .env
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "try { rs.status().ok } catch(e) { 0 }"
```

If returns `0`, initialize:

```bash
# Initialize with just primary first
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb-primary:27017'}]})"

# Wait 5 seconds
sleep 5

# Add secondaries
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.add('mongodb-secondary-1:27017'); rs.add('mongodb-secondary-2:27017')"
```

## Troubleshooting

### Issue: "Cannot connect without authentication"

**Cause**: MongoDB requires authentication (keyFile might be enabled)

**Solution**: Check if keyFile is commented out in docker-compose.yaml:

```bash
grep -A 5 "mongodb-primary:" docker-compose.yaml | grep keyFile
```

If you see `--keyFile`, you need to:
1. Stop containers
2. Comment out or remove `--keyFile` line
3. Restart
4. Create user
5. Re-enable keyFile (optional)

### Issue: "not primary" error

**Cause**: Replica set not initialized

**Solution**: Initialize replica set first (see Step 7)

### Issue: Container keeps restarting

**Check logs**:
```bash
docker-compose logs mongodb-primary | tail -30
```

Look for:
- Authentication errors
- KeyFile errors
- Port binding errors

### Issue: User creation fails

**Try without variables** (use actual values):
```bash
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "
    db.getSiblingDB('admin').createUser({
      user: 'rbdbuser',
      pwd: 'your_actual_password_here',
      roles: [{ role: 'root', db: 'admin' }]
    })
  "
```

Replace `your_actual_password_here` with the actual password from your `.env` file.

## Complete Manual Process

If everything else fails, here's the complete manual process:

```bash
# 1. Stop everything
docker-compose down

# 2. Check docker-compose.yaml - ensure --keyFile is commented out or removed
grep keyFile docker-compose.yaml

# 3. Start only primary (without keyFile)
docker-compose up -d mongodb-primary

# 4. Wait for it to start
sleep 15

# 5. Create user (replace PASSWORD with actual password)
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "
    db.getSiblingDB('admin').createUser({
      user: 'rbdbuser',
      pwd: 'PASSWORD',
      roles: [{ role: 'root', db: 'admin' }]
    })
  "

# 6. Verify
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "rbdbuser" \
  -p "PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"

# 7. Start everything
docker-compose up -d

# 8. Initialize replica set (after all nodes are up)
sleep 20
source .env
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb-primary:27017'}]})"

sleep 5

docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.add('mongodb-secondary-1:27017'); rs.add('mongodb-secondary-2:27017')"
```
