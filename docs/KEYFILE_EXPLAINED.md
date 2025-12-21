# MongoDB keyFile Explained

## What is keyFile?

The **keyFile** is a shared secret file used for **inter-node authentication** in MongoDB replica sets. It allows MongoDB nodes to authenticate with each other.

## When is keyFile Required?

### Required When:
- ✅ **Replica set with authorization enabled** (user authentication)
- ✅ MongoDB requires authentication (`MONGO_INITDB_ROOT_USERNAME` is set)
- ✅ You want secure inter-node communication

### Not Required When:
- ❌ Single MongoDB instance (no replica set)
- ❌ Replica set without authorization (no users)
- ❌ Development/testing where security is less critical

## Current Status

Looking at your `docker-compose.yaml`, **keyFile is currently disabled** (removed to allow user creation). This means:

- ✅ MongoDB works without keyFile
- ⚠️ **Less secure** - nodes can connect without shared secret
- ⚠️ Any process that can reach the MongoDB port can potentially join the replica set

## Should You Enable keyFile?

### For Production: **YES** ✅

**Benefits:**
- Prevents unauthorized nodes from joining replica set
- Adds layer of security for inter-node communication
- Best practice for production deployments

**Requirements:**
- User must exist (which you now have)
- Same keyFile on all nodes
- Proper permissions (600)

### For Development/Testing: **Optional**

If you're just testing or in a secure development environment, you can leave it disabled.

## How to Enable keyFile

### Step 1: Ensure User Exists

```bash
# Verify user exists and works
source .env
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"
```

### Step 2: Ensure keyFile Exists

```bash
# Check if keyFile exists
ls -la tls-certs/keyfile

# If not, generate it
./scripts/generate-keyfile.sh
```

### Step 3: Re-enable keyFile in docker-compose.yaml

Edit `docker-compose.yaml` and add `--keyFile` back to all three MongoDB services:

```yaml
mongodb-primary:
  # ... other config ...
  command: >
    mongod
    --replSet ${REPLICA_SET_NAME:-rs0}
    --keyFile /etc/mongo/ssl/keyfile    # <-- Add this line
    --tlsMode requireTLS
    # ... rest of command ...
```

Do the same for `mongodb-secondary-1` and `mongodb-secondary-2`.

### Step 4: Restart Services

```bash
docker-compose restart
```

## What keyFile Does

1. **Inter-Node Authentication**: Nodes use keyFile to prove they're authorized members
2. **Prevents Unauthorized Joins**: Without keyFile, any MongoDB instance could potentially join your replica set
3. **Works with User Auth**: keyFile handles node-to-node auth, while user credentials handle client-to-node auth

## Security Model

```
┌─────────────────────────────────────┐
│ Client → MongoDB Node               │
│ Uses: Username + Password           │
│ (SCRAM-SHA-256 authentication)     │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│ MongoDB Node → MongoDB Node        │
│ Uses: keyFile (shared secret)      │
│ (Inter-node authentication)        │
└─────────────────────────────────────┘
```

## Current Configuration

**Without keyFile** (current state):
- ✅ Works fine
- ✅ User authentication still works
- ⚠️ Less secure for inter-node communication
- ⚠️ Any MongoDB instance on the network could potentially join

**With keyFile** (recommended for production):
- ✅ More secure
- ✅ Prevents unauthorized nodes
- ✅ Best practice
- ⚠️ Requires user to exist first

## Recommendation

### For Your Current Setup:

Since you're running on a remote server and have the user created:

1. **Enable keyFile** for better security
2. It will work now that the user exists
3. Follow the steps above to re-enable it

### Quick Enable Script

```bash
# On remote server
cd ~/ha-mongodb

# 1. Verify user works
source .env
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"

# 2. Ensure keyFile exists
./scripts/generate-keyfile.sh

# 3. Edit docker-compose.yaml - add --keyFile to all 3 MongoDB services
nano docker-compose.yaml
# Add: --keyFile /etc/mongo/ssl/keyfile
# After: --replSet ${REPLICA_SET_NAME:-rs0}

# 4. Restart
docker-compose restart

# 5. Verify everything still works
docker-compose ps
docker-compose logs mongo-admin | tail -10
```

## Summary

- **keyFile is NOT required** for MongoDB to work
- **keyFile IS recommended** for production security
- **Current state**: Disabled (works, but less secure)
- **Action**: Re-enable after user exists (which you now have)

The keyFile provides an additional security layer for inter-node communication in replica sets. Since your setup is working, you can enable it when ready for production.
