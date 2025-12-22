# Fix: Replica Set Hostname Resolution Issue

## The Problem

Your connection string uses `localhost`, but MongoDB is still trying to connect to `mongodb-primary`. This happens because:

1. You connect to `localhost:27017` ✅
2. MongoDB discovers it's part of replica set `rs0`
3. MongoDB queries `rs.status()` to find all members
4. The replica set was initialized with `mongodb-primary:27017`, `mongodb-secondary-1:27017`, etc.
5. MongoDB tries to connect to these hostnames ❌ (they don't resolve outside Docker)

## Solution Options

### Option 1: Connect Without Replica Set Discovery (Quick Fix)

Temporarily remove `replicaSet=rs0` from your connection string to connect directly to localhost:

```bash
# In .env.local
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Note**: This works but you lose replica set benefits (automatic failover, read from secondaries, etc.)

### Option 2: Add Hostname Mapping (Recommended)

Add Docker hostnames to your system's `/etc/hosts` file so they resolve:

```bash
# On the server where your app runs
sudo nano /etc/hosts

# Add these lines:
127.0.0.1 mongodb-primary
127.0.0.1 mongodb-secondary-1
127.0.0.1 mongodb-secondary-2
```

**Note**: This only works if your app is on the same server as MongoDB.

### Option 3: Re-initialize Replica Set with Resolvable Hostnames (Best for Production)

Re-initialize the replica set with hostnames that your application can resolve.

#### Step 1: Check Current Replica Set Config

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

#### Step 2: Reconfigure Replica Set

If you need to change hostnames, you'll need to:
1. Stop the replica set
2. Clear data (⚠️ **This deletes all data!**)
3. Re-initialize with new hostnames

**Only do this if you can lose data or have backups!**

### Option 4: Use Direct Connection with Single Node (Simplest)

For development, connect directly to one node without replica set discovery:

```bash
# In .env.local - Remove replicaSet parameter
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

This connects only to the primary node and won't try to discover other members.

## Recommended: Option 2 (Add to /etc/hosts)

If your app runs on the same server as MongoDB:

```bash
# Add to /etc/hosts
echo "127.0.0.1 mongodb-primary mongodb-secondary-1 mongodb-secondary-2" | sudo tee -a /etc/hosts

# Verify
ping -c 1 mongodb-primary
# Should resolve to 127.0.0.1
```

Then your connection string with `replicaSet=rs0` will work because the hostnames will resolve.

## For Remote Apps (Different Server)

If your app runs on a **different server** than MongoDB:

### Option A: Use IP Addresses in Replica Set

You'd need to re-initialize the replica set with IP addresses, but this is complex and not recommended.

### Option B: Connect Without Replica Set

Use Option 1 or 4 - connect directly to one node without `replicaSet=rs0`.

### Option C: Use MongoDB Connection String with Direct Connection

MongoDB driver supports connecting to replica set even if you only specify one host:

```bash
# This should work - MongoDB will discover members but only connect to the ones it can resolve
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@YOUR_SERVER_IP:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin&directConnection=false
```

The `directConnection=false` (default) tells MongoDB to try replica set discovery, but it should still work if it can't reach all members.

## Quick Test

Try this connection string (removes replica set discovery):

```bash
# In .env.local
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

Restart your app and see if the error goes away.
