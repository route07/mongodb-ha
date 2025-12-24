# TLS CA Certificate: Client and Server Requirements

## Short Answer

**Yes, the client MUST use the same CA certificate (`ca.crt`) that was used to sign the server's certificate.**

## Why This Is Required

### How TLS Certificate Verification Works

1. **Server has a certificate** (`server.pem`) signed by a CA
2. **Client receives server's certificate** during TLS handshake
3. **Client verifies the certificate** using the CA certificate
4. **If CA matches**, client trusts the server ✅
5. **If CA doesn't match**, client rejects the connection ❌

### Certificate Chain

```
CA Certificate (ca.crt)
    ↓ (signs)
Server Certificate (server.pem)
    ↓ (presented to)
Client (verifies using ca.crt)
```

## Your Setup

Based on your configuration:

1. **Server certificates are signed by**: `tls-certs/ca.crt`
2. **Client must use**: The **same** `tls-certs/ca.crt` file

### Certificate Generation

Your setup generates certificates like this:

```bash
# 1. Generate CA certificate
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt

# 2. Sign server certificate with CA
openssl x509 -req -in server.csr -CA ca.crt -CAkey ca.key \
  -out server.crt

# 3. Server uses: server.pem (contains server.crt + server.key)
# 4. Client needs: ca.crt (to verify server.pem)
```

## Client Configuration

### Required: Use Same CA Certificate

**Connection String:**
```bash
mongodb://user:pass@localhost:27017/db?tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Key parameter**: `tlsCAFile=./tls-certs/ca.crt`

### What Happens If CA Doesn't Match?

**Without matching CA:**
```bash
# Client uses different CA
mongodb://user:pass@localhost:27017/db?tls=true&tlsCAFile=./wrong-ca.crt&authSource=admin
```

**Result**: ❌ Connection fails with certificate validation error

**With matching CA:**
```bash
# Client uses same CA
mongodb://user:pass@localhost:27017/db?tls=true&tlsCAFile=./tls-certs/ca.crt&authSource=admin
```

**Result**: ✅ Connection succeeds

## What About `tlsAllowInvalidCertificates`?

### Option 1: Use CA Certificate (Recommended)

```bash
# ✅ BEST: Use CA certificate for proper validation
mongodb://user:pass@localhost:27017/db?tls=true&tlsCAFile=./tls-certs/ca.crt&authSource=admin
```

**Benefits:**
- ✅ Proper certificate validation
- ✅ Security best practice
- ✅ Detects certificate tampering

### Option 2: Allow Invalid Certificates (Not Recommended)

```bash
# ⚠️ WORKS BUT INSECURE: Skip certificate validation
mongodb://user:pass@localhost:27017/db?tls=true&tlsAllowInvalidCertificates=true&authSource=admin
```

**When to use:**
- Development/testing only
- When you can't access the CA certificate
- **Not recommended for production**

**Risks:**
- ❌ No certificate validation
- ❌ Vulnerable to man-in-the-middle attacks
- ❌ Doesn't verify server identity

## Copying CA Certificate to Client

### If Client is on Same Server

```bash
# CA certificate is already available
./tls-certs/ca.crt
```

### If Client is on Different Server

**Step 1: Copy CA certificate to client server**

```bash
# From MongoDB server
scp ~/ha-mongodb/tls-certs/ca.crt user@client-server:~/your-app/tls-certs/ca.crt

# Or use rsync
rsync -avz ~/ha-mongodb/tls-certs/ca.crt user@client-server:~/your-app/tls-certs/
```

**Step 2: Update client connection string**

```bash
# On client server, use the copied CA certificate
MONGODB_URI=mongodb://user:pass@mongodb-server:27017/db?tls=true&tlsCAFile=./tls-certs/ca.crt&authSource=admin
```

**Step 3: Verify path is correct**

```bash
# On client server
ls -la ./tls-certs/ca.crt
# Should exist and be readable
```

## Code Examples

### Node.js / Mongoose

```javascript
const mongoose = require('mongoose');

// ✅ CORRECT: Use CA certificate
const uri = 'mongodb://user:pass@localhost:27017/db?tls=true&tlsCAFile=./tls-certs/ca.crt&authSource=admin';

mongoose.connect(uri, {
  tls: true,
  tlsCAFile: './tls-certs/ca.crt' // Same CA as server
});
```

### Node.js / Native Driver

```javascript
const { MongoClient } = require('mongodb');

// ✅ CORRECT: Use CA certificate
const client = new MongoClient('mongodb://user:pass@localhost:27017/db?tls=true&authSource=admin', {
  tls: true,
  tlsCAFile: './tls-certs/ca.crt' // Same CA as server
});
```

### Python / pymongo

```python
from pymongo import MongoClient
import ssl

# ✅ CORRECT: Use CA certificate
client = MongoClient(
    'mongodb://user:pass@localhost:27017/db?tls=true&authSource=admin',
    tls=True,
    tlsCAFile='./tls-certs/ca.crt'  # Same CA as server
)
```

## Multiple Servers / Replica Set

### All Servers Use Same CA

In a replica set, **all servers use certificates signed by the same CA**:

```bash
# All servers have:
# - server.pem (signed by ca.crt)
# - ca.crt (same CA certificate)

# Client uses same ca.crt for all connections
mongodb://user:pass@server1:27017,server2:27017,server3:27017/db?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&authSource=admin
```

**Important**: The CA certificate is the same across all servers, so one `ca.crt` file works for all connections.

## Production vs Development

### Development (Self-Signed Certificates)

**Your current setup:**
- ✅ Self-signed CA certificate
- ✅ Client uses same `ca.crt`
- ✅ Works for development/testing

**Connection:**
```bash
mongodb://user:pass@localhost:27017/db?tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

### Production (Trusted CA)

**If using certificates from a trusted CA (e.g., Let's Encrypt, commercial CA):**

**Option 1: Use system trust store**
```bash
# Client uses system CA bundle (no need to specify tlsCAFile)
mongodb://user:pass@localhost:27017/db?tls=true&authSource=admin
```

**Option 2: Use CA certificate file**
```bash
# Still specify CA if using custom CA
mongodb://user:pass@localhost:27017/db?tls=true&tlsCAFile=./tls-certs/ca.crt&authSource=admin
```

## Verification

### Test Certificate Match

**On server:**
```bash
# Check what CA signed the server certificate
openssl x509 -in tls-certs/server.pem -text -noout | grep "Issuer"
```

**On client:**
```bash
# Verify CA certificate matches
openssl x509 -in tls-certs/ca.crt -text -noout | grep "Subject"
```

**The Issuer of server.pem should match the Subject of ca.crt.**

### Test Connection

```bash
# Test with CA certificate (should work)
mongosh "mongodb://user:pass@localhost:27017/db?tls=true&tlsCAFile=./tls-certs/ca.crt&authSource=admin" \
  --eval "db.adminCommand('ping')"

# Expected: { ok: 1 }
```

## Common Issues

### Issue 1: CA Certificate Not Found

**Error**: `ENOENT: no such file or directory, open './tls-certs/ca.crt'`

**Fix**: Ensure CA certificate path is correct relative to your application

```javascript
// Use absolute path if needed
tlsCAFile: path.join(__dirname, 'tls-certs', 'ca.crt')
```

### Issue 2: Certificate Validation Failed

**Error**: `SSL peer certificate validation failed`

**Fix**: Ensure you're using the **same** CA certificate that signed the server certificate

```bash
# Verify CA matches
md5sum tls-certs/ca.crt  # On both server and client (should match)
```

### Issue 3: Different CA on Different Servers

**Error**: Connection works to one server but fails to another

**Fix**: All servers must use certificates signed by the same CA

```bash
# Regenerate certificates with same CA
./scripts/generate-tls-certs.sh

# Copy to all servers
scp -r tls-certs/ user@server:/path/to/ha-mongodb/
```

## Summary

| Question | Answer |
|----------|--------|
| **Does client need same CA?** | ✅ **YES** - Client must use the same CA certificate |
| **Why?** | To verify the server's certificate was signed by a trusted CA |
| **What if CA doesn't match?** | ❌ Connection fails with certificate validation error |
| **Can I skip validation?** | ⚠️ Yes, with `tlsAllowInvalidCertificates=true`, but **not recommended** |
| **Production?** | Use certificates from trusted CA or ensure all use same CA |

**Best Practice**: Always use the same CA certificate (`ca.crt`) on both client and server for proper TLS certificate validation.
