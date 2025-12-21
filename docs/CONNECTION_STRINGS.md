# MongoDB Connection Strings Guide

How to construct MongoDB URIs for different scenarios.

## Single Node Connection

For connecting to a single MongoDB instance (not replica set):

```bash
mongodb://username:password@host:port/database?tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Example:**
```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

## Replica Set Connection (Recommended for HA Setup)

For connecting to a replica set with all members:

```bash
mongodb://username:password@host1:port,host2:port,host3:port/database?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### For Local Connection

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Note**: Even with just `localhost:27017`, MongoDB driver will discover all replica set members automatically.

### For Remote Server Connection

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@YOUR_SERVER_IP:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### With All Members Explicitly Listed

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@mongodb-primary:27017,mongodb-secondary-1:27017,mongodb-secondary-2:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Note**: Use this format when connecting from within Docker network or when you have DNS resolution for all members.

## Connection String Components Explained

### Basic Format
```
mongodb://[username:password@]host[:port][/database][?options]
```

### Your Components

- **Username**: `rbdbuser`
- **Password**: `adsijeoirFgfsd092rvcsxvsdewRS`
- **Host**: 
  - Local: `localhost` or `127.0.0.1`
  - Remote: `YOUR_SERVER_IP` or domain name
  - Docker network: `mongodb-primary`, `mongodb-secondary-1`, `mongodb-secondary-2`
- **Port**: `27017`
- **Database**: `w3kyc`
- **Options**:
  - `replicaSet=rs0` - Replica set name (required for HA)
  - `tls=true` - Enable TLS
  - `tlsCAFile=./tls-certs/ca.crt` - CA certificate path
  - `tlsAllowInvalidCertificates=true` - Allow self-signed certs
  - `authSource=admin` - Authentication database

## Examples for Different Scenarios

### 1. Local Connection (Single Node - No Replica Set)

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### 2. Local Connection (Replica Set)

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### 3. Remote Server Connection (Replica Set)

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@YOUR_SERVER_IP:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### 4. From Within Docker Network

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@mongodb-primary:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=/etc/mongo/ssl/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Note**: Path to CA file is `/etc/mongo/ssl/ca.crt` inside container, not `./tls-certs/ca.crt`

### 5. With All Members (Explicit)

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@mongodb-primary:27017,mongodb-secondary-1:27017,mongodb-secondary-2:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

## URL Encoding

If your password contains special characters, URL encode them:

- `@` → `%40`
- `:` → `%3A`
- `/` → `%2F`
- `?` → `%3F`
- `#` → `%23`
- `[` → `%5B`
- `]` → `%5D`
- `%` → `%25`
- `&` → `%26`
- `=` → `%3D`
- `+` → `%2B`
- ` ` (space) → `%20`

**Example**: If password is `pass@word`, use `pass%40word`

## Using in Applications

### Node.js (Mongoose)

```javascript
const mongoose = require('mongoose');

const MONGODB_URI = process.env.MONGODB_URI || 
  'mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin';

mongoose.connect(MONGODB_URI, {
  // Additional options if needed
});

// Or with options object
mongoose.connect(MONGODB_URI, {
  tls: true,
  tlsCAFile: './tls-certs/ca.crt',
  tlsAllowInvalidCertificates: true,
  authSource: 'admin',
  replicaSet: 'rs0',
  readPreference: 'primaryPreferred' // Optional: can read from secondaries
});
```

### Node.js (Native Driver)

```javascript
const { MongoClient } = require('mongodb');

const uri = 'mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin';

const client = new MongoClient(uri, {
  tls: true,
  tlsCAFile: './tls-certs/ca.crt',
  tlsAllowInvalidCertificates: true,
  authSource: 'admin',
  replicaSet: 'rs0',
  readPreference: 'primaryPreferred'
});

await client.connect();
```

### Python (pymongo)

```python
from pymongo import MongoClient
import ssl

uri = "mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"

client = MongoClient(
    uri,
    tls=True,
    tlsCAFile='./tls-certs/ca.crt',
    tlsAllowInvalidCertificates=True,
    authSource='admin',
    replicaSet='rs0',
    read_preference='primaryPreferred'
)
```

## Connection String Builder

### For Your Setup

Based on your configuration:

```bash
# Base components
USERNAME="rbdbuser"
PASSWORD="adsijeoirFgfsd092rvcsxvsdewRS"
HOST="localhost"  # or YOUR_SERVER_IP for remote
PORT="27017"
DATABASE="w3kyc"
REPLICA_SET="rs0"

# Build URI
MONGODB_URI="mongodb://${USERNAME}:${PASSWORD}@${HOST}:${PORT}/${DATABASE}?replicaSet=${REPLICA_SET}&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"

echo $MONGODB_URI
```

## Quick Reference

### Your Current URI (Single Node)
```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### Updated for Replica Set (Recommended)
```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Only change**: Added `&replicaSet=rs0` (or `?replicaSet=rs0` if it's the first parameter)

## Testing Connection

### Using mongosh

```bash
mongosh "mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

### Using Node.js

```javascript
const { MongoClient } = require('mongodb');

const uri = 'mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin';

async function test() {
  const client = new MongoClient(uri);
  try {
    await client.connect();
    console.log('Connected!');
    const db = client.db('w3kyc');
    const collections = await db.listCollections().toArray();
    console.log('Collections:', collections);
  } finally {
    await client.close();
  }
}

test();
```

## Important Notes

1. **Replica Set Name**: Must match `REPLICA_SET_NAME` in your `.env` (default: `rs0`)
2. **TLS Required**: Your setup uses `requireTLS`, so `tls=true` is mandatory
3. **CA File Path**: 
   - Local: `./tls-certs/ca.crt` (relative to your app)
   - Docker: `/etc/mongo/ssl/ca.crt` (inside container)
4. **Auth Source**: Always use `authSource=admin` for root user
5. **Database**: `w3kyc` is your application database (can be any database name)

## Troubleshooting

### Connection Fails

1. **Check replica set is initialized**:
   ```bash
   docker exec mongo-primary mongosh --tls --tlsAllowInvalidCertificates --tlsCAFile /etc/mongo/ssl/ca.crt -u rbdbuser -p 'adsijeoirFgfsd092rvcsxvsdewRS' --authenticationDatabase admin --eval "rs.status()"
   ```

2. **Verify credentials**:
   ```bash
   docker exec mongo-primary mongosh --tls --tlsAllowInvalidCertificates --tlsCAFile /etc/mongo/ssl/ca.crt -u rbdbuser -p 'adsijeoirFgfsd092rvcsxvsdewRS' --authenticationDatabase admin --eval "db.adminCommand('ping')"
   ```

3. **Check TLS certificate path**:
   ```bash
   ls -la ./tls-certs/ca.crt  # Should exist
   ```

4. **Test connection without replica set** (temporarily):
   ```bash
   # Remove &replicaSet=rs0 from URI
   mongosh "mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
   ```
