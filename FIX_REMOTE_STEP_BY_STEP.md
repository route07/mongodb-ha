# Step-by-Step Fix for Remote Server

## The Problem

MongoDB is in replica set mode (`--replSet rs0`) but not initialized, so it won't accept writes (like creating users).

## Solution: Initialize Replica Set First

### Step 1: Initialize Replica Set with Primary Only

```bash
# On remote server
cd ~/ha-mongodb

# Initialize replica set (this works even without authentication)
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "rs.initiate({_id: 'rs0', members: [{_id: 0, host: 'mongodb-primary:27017'}]})"
```

**Expected**: `{ ok: 1 }`

### Step 2: Wait for Primary Election

```bash
# Wait 10 seconds
sleep 10

# Check if primary is elected
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "rs.isMaster().ismaster"
```

**Expected**: `true`

### Step 3: Now Create the User

```bash
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "
    db.getSiblingDB('admin').createUser({
      user: 'rbdbuser',
      pwd: 'adsijeoirFgfsd092rvcsxvsdewRS',
      roles: [{ role: 'root', db: 'admin' }]
    })
  "
```

**Expected**: `{ ok: 1 }`

### Step 4: Verify User Works

```bash
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "rbdbuser" \
  -p "adsijeoirFgfsd092rvcsxvsdewRS" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"
```

**Expected**: `{ ok: 1 }`

### Step 5: Add Secondary Nodes

```bash
# Make sure secondaries are running
docker-compose up -d mongodb-secondary-1 mongodb-secondary-2

# Wait for them to start
sleep 15

# Add them to replica set
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "rbdbuser" \
  -p "adsijeoirFgfsd092rvcsxvsdewRS" \
  --authenticationDatabase admin \
  --eval "rs.add('mongodb-secondary-1:27017')"

docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "rbdbuser" \
  -p "adsijeoirFgfsd092rvcsxvsdewRS" \
  --authenticationDatabase admin \
  --eval "rs.add('mongodb-secondary-2:27017')"
```

### Step 6: Verify Everything

```bash
# Check replica set status
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "rbdbuser" \
  -p "adsijeoirFgfsd092rvcsxvsdewRS" \
  --authenticationDatabase admin \
  --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"
```

**Expected**: Should show PRIMARY and SECONDARY nodes

### Step 7: Restart mongo-admin

```bash
docker-compose restart mongo-admin
sleep 10
docker-compose logs mongo-admin | tail -10
```

## Alternative: If Replica Set Init Fails

If `rs.initiate()` also fails, you need to temporarily remove `--replSet`:

```bash
# Stop primary
docker-compose stop mongodb-primary

# Edit docker-compose.yaml - comment out --replSet line
nano docker-compose.yaml
# Find: --replSet ${REPLICA_SET_NAME:-rs0}
# Comment: # --replSet ${REPLICA_SET_NAME:-rs0}

# Start primary
docker-compose up -d mongodb-primary
sleep 15

# Create user
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  --eval "
    db.getSiblingDB('admin').createUser({
      user: 'rbdbuser',
      pwd: 'adsijeoirFgfsd092rvcsxvsdewRS',
      roles: [{ role: 'root', db: 'admin' }]
    })
  "

# Verify
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "rbdbuser" \
  -p "adsijeoirFgfsd092rvcsxvsdewRS" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"

# Restore --replSet in docker-compose.yaml
# Then restart and initialize replica set
docker-compose restart
sleep 20
# Then run Step 1-6 above
```
