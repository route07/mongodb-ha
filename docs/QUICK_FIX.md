# Quick Fix Guide

## Current Issue

The warnings about `local.oplog.rs` are **harmless** - they just mean the replica set isn't initialized yet.

The **real issue** is authentication is failing, which prevents:
- Healthcheck from passing
- Replica set initialization
- mongo-admin from connecting

## Solution: Choose One

### Option 1: Fresh Start (Easiest - if you can lose data)

```bash
# Stop everything
docker-compose down

# Remove all data
rm -rf db_data_primary/ db_data_secondary1/ db_data_secondary2/

# Start fresh - MongoDB will create user automatically
docker-compose up -d

# Wait 60 seconds for everything to initialize
sleep 60

# Check status
docker-compose ps
docker-compose logs mongo-admin | tail -10
```

### Option 2: Fix User (Keep existing data)

```bash
# Run the fix script
./scripts/fix-user-quick.sh

# Restart everything
docker-compose restart

# Wait for initialization
sleep 30

# Check status
docker-compose ps
```

### Option 3: Manual Check

```bash
# Check if .env has correct credentials
cat .env | grep MONGO_INITDB

# Test authentication manually
source .env
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"
```

If authentication works, then initialize replica set:
```bash
./scripts/init-replica-set-manual.sh
```

## Expected Result

After fixing, you should see:
- ✅ All containers healthy
- ✅ Replica set initialized (no more oplog warnings)
- ✅ mongo-admin connected and showing 3 nodes
- ✅ Admin UI working at http://localhost:3000

## About the Warnings

The `local.oplog.rs not found` warnings are **normal** when:
- MongoDB is configured for replica set (`--replSet rs0`)
- But replica set hasn't been initialized yet

They will **disappear automatically** once the replica set is initialized.
