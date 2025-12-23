# Fix: SSL Certificate Validation Failed

## The Error

```
SSL peer certificate validation failed: authority and subject key identifier mismatch
```

## What This Means

MongoDB nodes are trying to connect to each other, but the TLS certificates don't match or are misconfigured. This can cause:
- Connection failures between nodes
- Replication issues
- Authentication problems

## Common Causes

### 1. Certificate Mismatch

Different nodes are using different certificates or certificates from different CAs.

**Check:**
```bash
# Compare CA certificates on all nodes
md5sum tls-certs/ca.crt  # On each server (should match!)
```

### 2. Wrong Certificate Used

A node is using the wrong certificate file (e.g., using client cert instead of server cert).

**Check:**
```bash
# On each server, verify correct certificate is mounted
docker exec mongo-primary ls -la /etc/mongo/ssl/
# Should show: ca.crt, server.pem, client.pem, keyfile
```

### 3. Certificate Not Properly Generated

Certificates were generated incorrectly or with wrong settings.

**Check certificate details:**
```bash
# Check server certificate
openssl x509 -in tls-certs/server.pem -text -noout | grep -A 5 "Subject Alternative Name"
```

### 4. Certificate Authority Mismatch

The CA certificate used to sign server certificates doesn't match the CA certificate used for validation.

## Solutions

### Solution 1: Regenerate Certificates (Recommended)

If certificates are mismatched, regenerate them properly:

```bash
cd ~/ha-mongodb

# Backup old certificates
mv tls-certs tls-certs.backup

# Regenerate certificates
./scripts/generate-tls-certs.sh

# Copy new certificates to ALL nodes
# On each server:
scp -r tls-certs/ user@server-ip:~/ha-mongodb/tls-certs/
```

**Important**: All nodes must use the **same CA certificate** and **same server certificates** (or certificates signed by the same CA).

### Solution 2: Verify Certificate Consistency

Ensure all nodes have identical certificates:

```bash
# On primary server
md5sum tls-certs/ca.crt
md5sum tls-certs/server.pem
md5sum tls-certs/keyfile

# On secondary-1 server (should match)
md5sum tls-certs/ca.crt
md5sum tls-certs/server.pem
md5sum tls-certs/keyfile

# On secondary-2 server (should match)
md5sum tls-certs/ca.crt
md5sum tls-certs/server.pem
md5sum tls-certs/keyfile
```

All MD5 hashes should be **identical** across all servers.

### Solution 3: Check Certificate Configuration

Verify docker-compose.yaml uses correct certificate paths:

```yaml
mongodb-primary:
  command: >
    mongod
    --tlsMode requireTLS
    --tlsCertificateKeyFile /etc/mongo/ssl/server.pem  # ← Server cert
    --tlsCAFile /etc/mongo/ssl/ca.crt                   # ← CA cert
    --tlsAllowConnectionsWithoutCertificates
```

### Solution 4: Use Same Certificates for All Nodes

For a replica set, you have two options:

**Option A: Same Server Certificate (Simpler)**
- Use the same `server.pem` on all nodes
- All nodes use the same certificate
- Works for internal cluster communication

**Option B: Node-Specific Certificates (More Secure)**
- Each node has its own certificate
- All certificates signed by the same CA
- CA certificate must be the same on all nodes

For your setup, **Option A is recommended** (simpler and works fine for internal communication).

## Quick Fix

### Step 1: Copy Certificates from Primary to All Nodes

```bash
# On primary server
cd ~/ha-mongodb

# Copy to secondary-1
scp -r tls-certs/ user@secondary-1-ip:~/ha-mongodb/tls-certs/

# Copy to secondary-2 (new server)
scp -r tls-certs/ user@192.168.2.6:~/ha-mongodb/tls-certs/
```

### Step 2: Verify Certificates Match

```bash
# On each server
md5sum tls-certs/ca.crt
md5sum tls-certs/server.pem
md5sum tls-certs/keyfile
```

All should match.

### Step 3: Restart Containers

```bash
# On each server
docker-compose restart
```

### Step 4: Check Logs

After restart, check if errors are gone:

```bash
docker logs mongo-primary 2>&1 | grep -i "ssl\|tls\|certificate" | tail -20
```

## Why This Happens

When you moved secondary-2 to a new server, you may have:
- Copied certificates that don't match the primary
- Generated new certificates on the new server
- Used certificates from a different CA

All nodes in a replica set must use certificates from the **same Certificate Authority**.

## Prevention

When setting up a new node:
1. **Always copy certificates from an existing node** (don't generate new ones)
2. **Verify MD5 hashes match** before starting the container
3. **Use the same CA certificate** on all nodes

## Summary

- ❌ **This is a problem** - certificate validation is failing
- ✅ **Fix**: Copy identical certificates to all nodes
- ✅ **Verify**: MD5 hashes should match on all servers
- ✅ **Restart**: Restart containers after copying certificates

The error will stop once all nodes use matching certificates from the same CA.
