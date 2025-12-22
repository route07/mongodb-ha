# Fix: getaddrinfo ENOTFOUND mongodb-primary

## Problem

Your application is trying to connect using `mongodb-primary` as the hostname, but this only works **inside the Docker network**. If your app runs outside Docker (on the same server or a different server), it can't resolve this hostname.

**Error:**
```
MongooseServerSelectionError: getaddrinfo ENOTFOUND mongodb-primary
```

## Solution

Replace `mongodb-primary` with either:
- `localhost` (if app is on the same server)
- `YOUR_SERVER_IP` (if app is on a different server)

## Quick Fix

### If Your App is on the Same Server

Update your connection string to use `localhost`:

```bash
# Before (doesn't work outside Docker)
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@mongodb-primary:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin

# After (works from same server)
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Key change**: `mongodb-primary` → `localhost`

### If Your App is on a Different Server

Use your MongoDB server's IP address:

```bash
# Replace YOUR_SERVER_IP with actual IP
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@YOUR_SERVER_IP:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Key change**: `mongodb-primary` → `YOUR_SERVER_IP`

## Why This Works

- **`mongodb-primary`**: Docker service name, only resolvable inside Docker network
- **`localhost`**: Works when app is on same server as MongoDB
- **`YOUR_SERVER_IP`**: Works when app is on different server

**Important**: Even with just `localhost:27017` or `IP:27017`, MongoDB will automatically discover all replica set members because you include `replicaSet=rs0` in the connection string.

## Where to Update

### Environment Variable (.env)

```bash
# .env file
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### Next.js / Node.js Config

```javascript
// .env.local or config file
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### Mongoose Connection

```javascript
// Make sure you're using the environment variable
const mongoose = require('mongoose');

const MONGODB_URI = process.env.MONGODB_URI || 
  'mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin';

mongoose.connect(MONGODB_URI);
```

## Verify Port is Exposed

Make sure MongoDB port is exposed in `docker-compose.yaml`:

```yaml
mongodb-primary:
  ports:
    - "${MONGO_PORT:-27017}:27017"  # Should expose port 27017
```

Check if port is listening:

```bash
# On MongoDB server
netstat -tlnp | grep 27017
# or
ss -tlnp | grep 27017
```

## Test Connection

### From Same Server

```bash
mongosh "mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

### From Different Server

```bash
# Make sure you have the CA cert file
mongosh "mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@YOUR_SERVER_IP:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

## Common Issues

### Issue: Still Can't Connect After Fix

**Check:**
1. MongoDB is running: `docker-compose ps`
2. Port is exposed: `docker-compose.yaml` has ports mapping
3. Firewall allows connection: `sudo ufw status`
4. TLS certificate path is correct: `ls -la ./tls-certs/ca.crt`

### Issue: Connection Works But Replica Set Not Found

**Solution**: Make sure `replicaSet=rs0` is in the connection string.

### Issue: TLS Certificate Error

**Solution**: 
- Verify `tlsCAFile` path is correct
- Make sure `tlsAllowInvalidCertificates=true` is set (for self-signed certs)
- Copy `ca.crt` to your application directory if needed

## Summary

✅ **Change**: `mongodb-primary` → `localhost` (same server) or `YOUR_SERVER_IP` (different server)  
✅ **Keep**: `replicaSet=rs0` in connection string  
✅ **Verify**: Port 27017 is exposed in docker-compose.yaml  
✅ **Test**: Connection works with mongosh before using in app
