# Testing MongoDB Replica Set Failover

## Overview

This guide walks you through testing automatic failover by stopping the primary container and verifying that:
1. A secondary is automatically elected as the new primary
2. Your client application can still connect and operate
3. The original primary rejoins as a secondary when restarted

## Prerequisites

- All replica set members are healthy
- Client connection string includes all members
- Client has appropriate timeouts configured

## Step-by-Step Test

### Step 1: Check Initial State

Before starting, verify the current replica set status:

```bash
cd ~/ha-mongodb
source .env

# Check which node is currently primary
./scripts/check-replica-set-status.sh
```

**Expected output:**
```
Members:
  mongodb-primary:27017: PRIMARY ⭐ (✓ healthy)
  mongodb-secondary-1:27017: SECONDARY (✓ healthy)
  mongodb-secondary-2:27017: SECONDARY (✓ healthy)
```

Note which node is PRIMARY (likely `mongodb-primary`).

### Step 2: Verify Client Connection

Test that your client can connect before the test:

```bash
# Test connection
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"
```

**Expected**: `{ ok: 1 }`

### Step 3: Stop the Primary Container

```bash
# Stop the primary container
docker-compose stop mongodb-primary

# Or using docker directly
docker stop mongo-primary
```

**What happens:**
- Primary container stops
- Replica set detects the primary is unreachable
- Secondaries initiate an election (takes 10-30 seconds)
- One secondary becomes the new primary

### Step 4: Wait for Election (30-60 seconds)

**Important**: Give MongoDB time to detect the failure and elect a new primary.

```bash
# Wait 30 seconds
sleep 30

# Check status from a secondary
docker exec mongo-secondary-1 mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"
```

**Expected output** (after election):
```
mongodb-primary:27017: (not reachable/healthy)
mongodb-secondary-1:27017: PRIMARY ⭐
mongodb-secondary-2:27017: SECONDARY
```

**Note**: One of the secondaries should now be PRIMARY.

### Step 5: Verify Client Can Still Connect

Test that your client can still connect using the connection string:

```bash
# Test connection (driver will discover new primary)
mongosh "mongodb://${MONGO_INITDB_ROOT_USERNAME}:${MONGO_INITDB_ROOT_PASSWORD}@localhost:27017,localhost:27018,localhost:27019/?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin" \
  --eval "db.adminCommand('ping')"
```

**Expected**: `{ ok: 1 }` - Connection succeeds, driver automatically found new primary.

### Step 6: Test Write Operations

Verify you can still write to the new primary:

```bash
# Connect and insert a test document
mongosh "mongodb://${MONGO_INITDB_ROOT_USERNAME}:${MONGO_INITDB_ROOT_PASSWORD}@localhost:27017,localhost:27018,localhost:27019/testdb?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin" \
  --eval "db.test.insertOne({ test: 'failover', timestamp: new Date() })"
```

**Expected**: Document inserted successfully.

### Step 7: Restart Original Primary

Restart the original primary container:

```bash
# Start the primary container
docker-compose start mongodb-primary

# Or using docker directly
docker start mongo-primary

# Wait for it to start and sync
sleep 20
```

### Step 8: Verify Original Primary Rejoins

Check that the original primary rejoins as a secondary:

```bash
# Check replica set status
docker exec mongo-secondary-1 mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr + ' (health: ' + m.health + ')'))"
```

**Expected output**:
```
mongodb-primary:27017: SECONDARY (health: 1)
mongodb-secondary-1:27017: PRIMARY ⭐ (health: 1)
mongodb-secondary-2:27017: SECONDARY (health: 1)
```

**Note**: The original primary (`mongodb-primary`) is now a SECONDARY and syncing data from the current primary.

### Step 9: (Optional) Move Primary Back

If you want the primary back on `mongodb-primary`:

```bash
# Connect to current primary
docker exec mongo-secondary-1 mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.stepDown(60)"

# Wait for re-election
sleep 30

# Check if mongodb-primary is now primary
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.isMaster().ismaster"
```

**Expected**: `true` (if mongodb-primary was elected)

## What to Expect

### During Failover (10-30 seconds)

1. **Primary stops** → Container stops responding
2. **Election starts** → Secondaries detect primary is down
3. **New primary elected** → One secondary becomes PRIMARY
4. **Client reconnects** → Driver discovers new primary automatically

### After Failover

- ✅ One secondary is now PRIMARY
- ✅ Client can still connect (if connection string includes all members)
- ✅ Writes work on new primary
- ✅ Reads work (from new primary or secondaries)
- ✅ Original primary shows as DOWN or (not reachable/healthy)

### After Restarting Original Primary

- ✅ Original primary rejoins as SECONDARY
- ✅ Syncs data from current primary
- ✅ All nodes healthy again
- ✅ Primary remains on the node that was elected (unless you step it down)

## Troubleshooting

### Issue: No Primary After Stopping Primary

**Symptom**: All nodes show as SECONDARY after stopping primary

**Causes**:
- Not enough healthy nodes for quorum (need majority: 2 out of 3)
- Election timeout too short
- Network issues

**Fix**:
```bash
# Wait longer (up to 60 seconds)
sleep 60

# Check status again
./scripts/check-replica-set-status.sh
```

### Issue: Client Can't Connect After Failover

**Symptom**: Client times out or can't find primary

**Causes**:
- Connection string doesn't include all members
- Timeout too short
- Client not configured for replica set

**Fix**:
1. Ensure connection string includes all members:
   ```bash
   mongodb://user:pass@localhost:27017,localhost:27018,localhost:27019/db?replicaSet=rs0&...
   ```

2. Increase timeouts:
   ```javascript
   {
     serverSelectionTimeoutMS: 30000, // 30 seconds
     connectTimeoutMS: 30000
   }
   ```

3. Verify replica set name matches: `replicaSet=rs0`

### Issue: Original Primary Doesn't Rejoin

**Symptom**: After restarting, original primary doesn't sync

**Fix**:
```bash
# Check logs
docker logs mongo-primary | tail -50

# Verify it can reach other nodes
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status()"
```

Usually resolves automatically. If not, check network connectivity.

## Quick Test Script

Here's a quick script to test failover:

```bash
#!/bin/bash
# Quick failover test

cd ~/ha-mongodb
source .env

echo "1. Checking initial state..."
./scripts/check-replica-set-status.sh

echo ""
echo "2. Stopping primary..."
docker-compose stop mongodb-primary

echo ""
echo "3. Waiting 30 seconds for election..."
sleep 30

echo ""
echo "4. Checking new primary..."
docker exec mongo-secondary-1 mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"

echo ""
echo "5. Restarting original primary..."
docker-compose start mongodb-primary

echo ""
echo "6. Waiting 20 seconds for sync..."
sleep 20

echo ""
echo "7. Final status..."
./scripts/check-replica-set-status.sh
```

## Best Practices for Testing

1. **Test in non-production first** - Failover works, but test safely
2. **Monitor during test** - Watch logs and status
3. **Test client reconnection** - Verify your app handles failover
4. **Test with load** - Run some queries during failover
5. **Document results** - Note how long election took, which node became primary

## Summary

✅ **Stopping the primary is a valid test** - This is exactly how failover works in production

✅ **Expected behavior:**
- Secondary automatically becomes primary (10-30 seconds)
- Client reconnects automatically (if configured correctly)
- Original primary rejoins as secondary when restarted

✅ **Key requirements:**
- Connection string includes all members
- Appropriate timeouts configured
- Replica set properly initialized

This test validates that your HA setup works correctly!
