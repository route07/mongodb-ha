# Fix: Primary on Wrong Node / Connection Timeout

## The Problem

Your replica set has a PRIMARY, but it's on `mongodb-secondary-1`, not `mongodb-primary`. Your app is getting connection timeouts because:

1. App connects to `localhost` or `dbServer` ✅
2. MongoDB discovers replica set `rs0`
3. App tries to connect to discovered members
4. If connection string or discovery points to `mongodb-primary` (which is SECONDARY), it times out ❌

## Solutions

### Solution 1: Ensure Connection String Uses Resolvable Hostname

Make sure your `.env.local` uses `localhost` or the server IP, **not** `mongodb-primary`:

```bash
# ✅ CORRECT - Uses localhost (or dbServer IP)
MONGODB_URI=mongodb://rbdbuser:password@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin

# ❌ WRONG - Uses mongodb-primary hostname
MONGODB_URI=mongodb://rbdbuser:password@mongodb-primary:27017/w3kyc?replicaSet=rs0&...
```

### Solution 2: Increase Connection Timeout

The timeout might be too short (5000ms). Increase it in your connection options:

**In `src/lib/mongodb.ts`:**

```typescript
const opts = {
  bufferCommands: false,
  maxPoolSize: 10,
  minPoolSize: 2,
  maxIdleTimeMS: 30000,
  serverSelectionTimeoutMS: 30000, // ← Increase from 5000 to 30000
  socketTimeoutMS: 45000,
  connectTimeoutMS: 30000, // ← Increase from 10000 to 30000
};
```

### Solution 3: Add readPreference

Allow reading from secondaries if primary is temporarily unavailable:

```typescript
const opts = {
  // ... existing options ...
  readPreference: 'primaryPreferred', // ← Add this
  // This allows reading from secondary if primary is unavailable
};
```

### Solution 4: Move Primary Back to mongodb-primary (Optional)

If you want the primary on `mongodb-primary` for consistency:

```bash
cd ~/ha-mongodb
source .env

# Connect to current primary (mongodb-secondary-1)
docker exec mongodb-secondary-1 mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
    // Step down current primary
    rs.stepDown(60);
    print('Stepped down. Waiting for re-election...');
  "

# Wait 30 seconds
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

**Note**: The primary can change during failover - this is normal MongoDB behavior. Your app should handle this automatically.

## Recommended Fix (Combination)

1. **Update connection string** to use `localhost` or server IP (not `mongodb-primary`)
2. **Increase timeouts** in your Mongoose options (from 5000ms to 30000ms)
3. **Add `readPreference: 'primaryPreferred'`** to allow reading from secondaries

This makes your app resilient to primary changes.

## For Remote Server (Your Case)

Since you're on a remote server with `dbServer` hostname:

1. **Make sure connection string uses `dbServer` or IP, not `mongodb-primary`:**
   ```bash
   # In .env.local
   MONGODB_URI=mongodb://rbdbuser:password@dbServer:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
   ```

2. **Add MongoDB hostnames to /etc/hosts** (if not already done):
   ```bash
   sudo sh -c 'echo "192.168.10.2 mongodb-primary mongodb-secondary-1 mongodb-secondary-2" >> /etc/hosts'
   ```

3. **Update Mongoose options** to increase timeouts and add readPreference

## Quick Test

Update your `src/lib/mongodb.ts`:

```typescript
const opts = {
  bufferCommands: false,
  maxPoolSize: 10,
  minPoolSize: 2,
  maxIdleTimeMS: 30000,
  serverSelectionTimeoutMS: 30000, // Increased
  socketTimeoutMS: 45000,
  connectTimeoutMS: 30000, // Increased
  readPreference: 'primaryPreferred', // Added
};
```

And ensure your `.env.local` uses `localhost` or server IP, not `mongodb-primary`.

Then restart your app.
