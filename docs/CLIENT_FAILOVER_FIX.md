# Fix: Client Can't Connect After Primary Stops

## The Problem

After stopping the primary container, your client can't connect even though:
- ✅ Failover worked (secondary became primary)
- ✅ Replica set is healthy
- ✅ New primary is accessible

## Root Cause

Your client connection string likely only includes the primary port (`localhost:27017`), which is now stopped. The client needs to include **all replica set members** so it can discover the new primary.

## Solution: Update Connection String

### Current (Broken) Connection String

```bash
# ❌ Only connects to stopped primary
mongodb://user:pass@localhost:27017/db?replicaSet=rs0&tls=...
```

### Fixed Connection String (Include All Members)

```bash
# ✅ Includes all members - driver will find new primary
mongodb://user:pass@localhost:27017,localhost:27018,localhost:27019/db?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Key change**: Added `,localhost:27018,localhost:27019` to include all members.

## Quick Test

Test the connection with all members:

```bash
cd ~/ha-mongodb
source .env

mongosh "mongodb://${MONGO_INITDB_ROOT_USERNAME}:${MONGO_INITDB_ROOT_PASSWORD}@localhost:27017,localhost:27018,localhost:27019/?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin" \
  --eval "db.adminCommand('ping')"
```

**Expected**: `{ ok: 1 }` - Connection succeeds!

## Alternative: Connect Directly to New Primary

If you need immediate access, connect directly to the new primary:

```bash
# Connect directly to secondary-1 (now primary) on port 27018
mongosh "mongodb://${MONGO_INITDB_ROOT_USERNAME}:${MONGO_INITDB_ROOT_PASSWORD}@localhost:27018/?directConnection=true&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin" \
  --eval "db.adminCommand('ping')"
```

**Note**: `directConnection=true` bypasses replica set discovery and connects directly to that node.

## Update Your Application

### Node.js / Mongoose

**Before:**
```javascript
const uri = 'mongodb://user:pass@localhost:27017/db?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin';
```

**After:**
```javascript
const uri = 'mongodb://user:pass@localhost:27017,localhost:27018,localhost:27019/db?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin';
```

### Python / pymongo

**Before:**
```python
uri = "mongodb://user:pass@localhost:27017/db?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

**After:**
```python
uri = "mongodb://user:pass@localhost:27017,localhost:27018,localhost:27019/db?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

## Why This Works

1. **Connection String with All Members**: 
   - Client tries to connect to each member in order
   - If first member (27017) is down, tries next (27018)
   - Finds the new primary and connects

2. **Replica Set Discovery**:
   - Once connected to any member, driver queries replica set status
   - Discovers which node is currently PRIMARY
   - Routes operations to the primary automatically

3. **Automatic Failover**:
   - If current connection fails, driver tries other members
   - Automatically reconnects to new primary

## Important Notes

### Even with Single Entry, Discovery Works (Sometimes)

If your connection string only has `localhost:27017` but includes `replicaSet=rs0`:
- ✅ MongoDB driver **will** discover other members
- ⚠️ But if the first connection fails, discovery may timeout
- ✅ **Best practice**: Include all members explicitly

### Timeout Configuration

If connection still fails, increase timeouts:

```javascript
const client = new MongoClient(uri, {
  serverSelectionTimeoutMS: 30000, // 30 seconds (default: 5 seconds)
  connectTimeoutMS: 30000,
  socketTimeoutMS: 45000
});
```

## Verify Your Connection String

Check what your client is actually using:

```bash
# In your application, log the connection string (without password)
console.log('MongoDB URI:', uri.replace(/:[^:@]+@/, ':****@'));
```

Make sure it includes all three ports: `27017,27018,27019`

## Summary

✅ **Failover worked correctly** - Secondary became primary

❌ **Client connection issue** - Connection string only included stopped primary

✅ **Solution** - Include all members: `localhost:27017,localhost:27018,localhost:27019`

After updating your connection string, the client will automatically connect to the new primary even when the original primary is stopped!
