# MongoDB Connection String for App Servers

## Overview

Your app servers need to connect to MongoDB. The connection string depends on where your app runs relative to MongoDB.

## Connection String Options

### Option 1: App on Same Server as MongoDB Primary

If your app runs on the **same server** as the MongoDB primary:

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Requirements:**
- CA certificate file at `./tls-certs/ca.crt` (relative to your app)
- App can resolve `localhost` to MongoDB

### Option 2: App on Different Server (Recommended)

If your app runs on a **different server** than MongoDB:

```bash
# Use MongoDB server IP or hostname
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@192.168.2.1:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Replace `192.168.2.1` with:**
- Your MongoDB primary server IP, OR
- A hostname that resolves to MongoDB server, OR
- A load balancer IP (if using one)

**Requirements:**
- Copy `ca.crt` to your app server: `./tls-certs/ca.crt`
- Network connectivity to MongoDB server
- Firewall allows port 27017

### Option 3: Multiple Replica Set Members (Best for HA)

For better availability, list multiple members:

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@192.168.2.1:27017,192.168.2.2:27017,192.168.2.6:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Benefits:**
- App can connect even if one node is down
- Automatic failover
- Better resilience

**Note:** Even with just one host, MongoDB will discover all members automatically if `replicaSet=rs0` is set.

## Setup Steps for App Servers

### Step 1: Copy CA Certificate

Copy the CA certificate to your app server:

```bash
# From MongoDB server
scp ~/ha-mongodb/tls-certs/ca.crt user@app-server:~/your-app/tls-certs/ca.crt

# Or create directory and copy
mkdir -p ~/your-app/tls-certs
scp ~/ha-mongodb/tls-certs/ca.crt user@app-server:~/your-app/tls-certs/
```

### Step 2: Set Connection String

In your app's `.env.local` or environment:

```bash
# For app on different server
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@MONGODB_SERVER_IP:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### Step 3: Use Environment Variables (Recommended)

Instead of hardcoding, use separate variables:

```bash
# .env.local on app server
MONGODB_HOST=192.168.2.1              # MongoDB server IP
MONGODB_PORT=27017
MONGODB_USERNAME=rbdbuser
MONGODB_PASSWORD=adsijeoirFgfsd092rvcsxvsdewRS
MONGODB_DATABASE=w3kyc
MONGODB_REPLICA_SET=rs0
MONGODB_TLS_CA_FILE=./tls-certs/ca.crt
MONGODB_TLS_ALLOW_INVALID=true
```

Then build the URI in your code (see `docs/BUILD_CONNECTION_STRING.md`).

## Examples by Scenario

### Scenario 1: App on MongoDB Server

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### Scenario 2: App on Separate Server

```bash
# Single entry point (MongoDB will discover all members)
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@192.168.2.1:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### Scenario 3: Multiple Entry Points (Explicit)

```bash
# List all members explicitly
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@192.168.2.1:27017,192.168.2.2:27017,192.168.2.6:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### Scenario 4: Using Hostname

If you have DNS configured:

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@mongodb.example.com:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

## Important Notes

### 1. CA Certificate Path

The `tlsCAFile` path is **relative to your application**, not the MongoDB server:

```bash
# If your app is at: /home/user/my-app/
# And certificate is at: /home/user/my-app/tls-certs/ca.crt
# Use: ./tls-certs/ca.crt

# Or absolute path:
# Use: /home/user/my-app/tls-certs/ca.crt
```

### 2. Replica Set Discovery

Even with just **one host** in the connection string, MongoDB will:
- Connect to that host
- Discover it's part of replica set `rs0`
- Automatically find all other members
- Connect to the PRIMARY for writes
- Use secondaries for reads (if configured)

So you don't need to list all members - one is enough!

### 3. Firewall Configuration

Ensure your app server can reach MongoDB:

```bash
# Test connectivity
ping MONGODB_SERVER_IP
telnet MONGODB_SERVER_IP 27017
# Or
nc -zv MONGODB_SERVER_IP 27017
```

### 4. Connection Options

Your Mongoose/Node.js options should include:

```typescript
const opts = {
  serverSelectionTimeoutMS: 30000,  // Give time to discover replica set
  socketTimeoutMS: 45000,
  connectTimeoutMS: 30000,
  readPreference: 'primaryPreferred',  // Can read from secondary if needed
};
```

## Quick Setup Checklist

For each app server:

- [ ] Copy `ca.crt` to app server: `./tls-certs/ca.crt`
- [ ] Set `MONGODB_URI` with correct server IP (not localhost if different server)
- [ ] Include `replicaSet=rs0` in connection string
- [ ] Include `tls=true` and `tlsCAFile` path
- [ ] Test connectivity: `nc -zv MONGODB_SERVER_IP 27017`
- [ ] Verify firewall allows connection
- [ ] Test connection from app

## Summary

**For app on different server:**
```bash
MONGODB_URI=mongodb://rbdbuser:password@MONGODB_SERVER_IP:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Key changes from your example:**
- `localhost` → `MONGODB_SERVER_IP` (if app is on different server)
- Keep `replicaSet=rs0` (MongoDB will discover all members)
- Keep `tlsCAFile=./tls-certs/ca.crt` (relative to your app directory)
- Copy `ca.crt` to your app server
