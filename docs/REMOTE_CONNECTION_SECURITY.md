# Remote Connection Security Guide

## Security Layers for Remote MongoDB Access

When connecting to MongoDB from remote servers, you need multiple security layers:

### 1. Client-to-Node Authentication (User Auth) ✅ You Have This
- Username/password authentication
- Protects against unauthorized client connections
- **You have this**: `rbdbuser` with password

### 2. Inter-Node Authentication (keyFile) ⚠️ Currently Disabled
- Shared secret between MongoDB nodes
- Prevents unauthorized nodes from joining replica set
- **Currently disabled** in your setup

### 3. Network Security
- Firewall rules
- TLS encryption
- **You have TLS** ✅

## Why keyFile Matters for Remote Connections

### Without keyFile (Current State):
```
Remote Client → MongoDB Node ✅ (Protected by user auth)
MongoDB Node → MongoDB Node ⚠️ (No keyFile protection)
```

**Risk**: If someone gains access to your network, they could:
- Start a malicious MongoDB instance
- Potentially join your replica set
- Access replicated data

### With keyFile (Recommended):
```
Remote Client → MongoDB Node ✅ (Protected by user auth)
MongoDB Node → MongoDB Node ✅ (Protected by keyFile)
```

**Benefit**: Even if someone is on your network, they can't join the replica set without the keyFile.

## Recommendation: Enable keyFile

Since you're connecting from remote servers, **enable keyFile** for better security.

## How to Enable keyFile

### Step 1: Verify User Exists and Works

```bash
# On remote server
cd ~/ha-mongodb
source .env

docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"
```

**Expected**: `{ ok: 1 }`

### Step 2: Ensure keyFile Exists

```bash
# Check if keyFile exists
ls -la tls-certs/keyfile

# If not, generate it
./scripts/generate-keyfile.sh
```

### Step 3: Enable keyFile in docker-compose.yaml

Edit `docker-compose.yaml` and add `--keyFile` to all three MongoDB services:

```yaml
mongodb-primary:
  command: >
    mongod
    --replSet ${REPLICA_SET_NAME:-rs0}
    --keyFile /etc/mongo/ssl/keyfile    # <-- Add this
    --tlsMode requireTLS
    # ... rest ...
```

Do the same for `mongodb-secondary-1` and `mongodb-secondary-2`.

### Step 4: Restart Services

```bash
docker-compose restart

# Wait for services to start
sleep 20

# Verify everything works
docker-compose ps
docker-compose logs mongo-admin | tail -10
```

## Additional Security for Remote Connections

### 1. Firewall Rules

```bash
# Only allow specific IPs to connect
sudo ufw allow from YOUR_TRUSTED_IP to any port 27017
sudo ufw allow from YOUR_TRUSTED_IP to any port 3000

# Or use SSH tunnel (more secure)
```

### 2. SSH Tunnel (Recommended)

Instead of exposing MongoDB port directly:

```bash
# From your local machine
ssh -L 27017:localhost:27017 user@YOUR_SERVER_IP

# Then connect locally
mongosh "mongodb://rbdbuser:password@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

### 3. Network Security Groups (Cloud)

If using AWS/Azure/GCP:
- Restrict MongoDB port to specific IPs
- Use VPC/private networks
- Don't expose to 0.0.0.0/0

### 4. Connection String Security

For remote connections, use:

```bash
# With replica set
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@YOUR_SERVER_IP:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

**Important**: 
- Use strong passwords
- Keep TLS enabled
- Use `tlsAllowInvalidCertificates=true` only if using self-signed certs
- For production, use proper CA-signed certificates

## Security Checklist for Remote Access

- [ ] Strong MongoDB password set
- [ ] keyFile enabled (inter-node auth)
- [ ] TLS enabled (encryption in transit)
- [ ] Firewall configured (restrict access)
- [ ] SSH tunnel considered (instead of direct exposure)
- [ ] Network security groups configured (if cloud)
- [ ] Regular backups scheduled
- [ ] Monitoring/alerting set up

## Summary

**For remote connections, you should enable keyFile** because:

1. ✅ You have the user created (prerequisite met)
2. ✅ Remote access increases attack surface
3. ✅ keyFile adds important security layer
4. ✅ Prevents unauthorized nodes from joining
5. ✅ Best practice for production

**Your connection string remains the same** - keyFile doesn't affect how clients connect, only how nodes authenticate with each other.
