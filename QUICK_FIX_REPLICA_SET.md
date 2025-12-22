# Quick Fix: Replica Set Hostname Issue

## Your Problem

Connection string has `localhost` ✅, but MongoDB still tries `mongodb-primary` ❌

**Why**: When you use `replicaSet=rs0`, MongoDB discovers all members. The replica set was initialized with `mongodb-primary` hostnames that don't resolve outside Docker.

## Quick Fix (2 Options)

### Option 1: Remove Replica Set Discovery (Fastest)

**Change your `.env.local`:**

```bash
# Remove &replicaSet=rs0
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Restart your app.** This connects directly to localhost without trying to discover replica set members.

### Option 2: Add Hostname Mapping (If Same Server)

**If your app runs on the same server as MongoDB:**

```bash
# Add to /etc/hosts
sudo sh -c 'echo "127.0.0.1 mongodb-primary mongodb-secondary-1 mongodb-secondary-2" >> /etc/hosts'

# Verify
ping -c 1 mongodb-primary
```

**Keep your `.env.local` as is** (with `replicaSet=rs0`). Now the hostnames will resolve.

## Which Option?

- **Same server**: Use Option 2 (add to /etc/hosts) - keeps replica set benefits
- **Different server**: Use Option 1 (remove replicaSet) - simpler, works immediately
- **Need HA features**: Use Option 2 or re-initialize replica set with resolvable hostnames

## Test

After applying the fix, restart your app. The error should be gone!
