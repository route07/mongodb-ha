# Fix: ECONNREFUSED 127.0.0.1:27017 on Remote Server

## The Problem

Your app connects to `dbServer:27017` (which resolves to `192.168.10.2`), but MongoDB is trying to connect to `127.0.0.1:27017`. This happens because:

1. You connect to `dbServer:27017` ✅
2. MongoDB discovers replica set `rs0`
3. Replica set members are configured with `localhost` or `127.0.0.1` as hostnames
4. MongoDB tries to connect to those hostnames ❌ (they resolve to your app server, not MongoDB server)

## Solution: Check Replica Set Configuration

### Step 1: Check What Hostnames the Replica Set Uses

On your **MongoDB server** (where MongoDB is running):

```bash
cd ~/ha-mongodb
source .env

docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status().members.forEach(m => print(m.name))"
```

This will show the hostnames like:
- `mongodb-primary:27017`
- `localhost:27017`
- `127.0.0.1:27017`
- etc.

### Step 2: Fix Based on What You See

#### If you see `mongodb-primary`, `mongodb-secondary-1`, etc.:

Add these to `/etc/hosts` on your **application server** (where your app runs):

```bash
# On your app server (w3kyc-1)
sudo sh -c 'echo "192.168.10.2 mongodb-primary mongodb-secondary-1 mongodb-secondary-2" >> /etc/hosts'

# Verify
ping -c 1 mongodb-primary
# Should resolve to 192.168.10.2
```

#### If you see `localhost:27017` or `127.0.0.1:27017`:

The replica set was initialized with localhost hostnames. You need to either:

**Option A: Re-initialize replica set with proper hostnames** (if you can lose data):

```bash
# On MongoDB server
cd ~/ha-mongodb
docker-compose down
rm -rf db_data_primary/ db_data_secondary1/ db_data_secondary2/
# Then re-initialize with proper hostnames
```

**Option B: Use connection string without replica set discovery**:

```bash
# In .env.local on app server
MONGODB_URI=mongodb://rbdbuser:password@dbServer:27017/w3kyc?tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
# Remove &replicaSet=rs0
```

## Quick Fix: Try This First

### Option 1: Add MongoDB Hostnames to /etc/hosts

On your **application server** (`w3kyc-1`):

```bash
# Add MongoDB Docker hostnames pointing to MongoDB server IP
sudo sh -c 'echo "192.168.10.2 mongodb-primary mongodb-secondary-1 mongodb-secondary-2" >> /etc/hosts'

# Verify
ping -c 1 mongodb-primary
# Should show 192.168.10.2
```

Then keep your connection string as is (with `replicaSet=rs0`).

### Option 2: Remove Replica Set Discovery

If Option 1 doesn't work, remove replica set from connection string:

```bash
# In .env.local
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@dbServer:27017/w3kyc?tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
# Remove &replicaSet=rs0
```

## Verify the Fix

After applying the fix:

1. **Restart your application**
2. **Check logs** - should no longer see `ECONNREFUSED 127.0.0.1:27017`
3. **Test connection** - app should connect successfully

## If Still Not Working

Check what hostnames the replica set actually uses:

```bash
# On MongoDB server
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status()" | grep -E "name|host"
```

Then add those exact hostnames to `/etc/hosts` on your app server, pointing to `192.168.10.2`.
