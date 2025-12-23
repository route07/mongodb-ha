# Fix: Secondary Node Unreachable/Unhealthy

## The Problem

After moving a secondary to a new server, it shows as:
- `(not reachable/healthy)`
- `(✗ unhealthy)`

This means the replica set nodes can't communicate with the new secondary.

## Common Causes & Fixes

### 1. MongoDB Not Running on New Server

**Check:**
```bash
# On new server
docker ps | grep mongo-secondary-2
docker-compose ps
```

**Fix:**
```bash
# Start the container
docker-compose up -d mongodb-secondary-2

# Check logs
docker logs mongo-secondary-2
```

### 2. Firewall Blocking Port 27017

**Check:**
```bash
# On new server
sudo ufw status
netstat -tlnp | grep 27017
```

**Fix:**
```bash
# On new server - Allow MongoDB port from other servers
sudo ufw allow from 192.168.2.1 to any port 27017  # Primary server IP
sudo ufw allow from 192.168.2.2 to any port 27017  # Secondary-1 server IP

# Or allow from entire subnet
sudo ufw allow from 192.168.2.0/24 to any port 27017
```

### 3. MongoDB Not Bound to All Interfaces

**Check:**
```bash
# On new server
docker exec mongo-secondary-2 netstat -tlnp | grep 27017
```

Should show: `0.0.0.0:27017` (not `127.0.0.1:27017`)

**Fix:** Ensure `docker-compose.yaml` has `--bind_ip_all` in the command:

```yaml
command: >
  mongod
  --replSet ${REPLICA_SET_NAME:-rs0}
  --keyFile /etc/mongo/ssl/keyfile
  --tlsMode requireTLS
  --tlsCertificateKeyFile /etc/mongo/ssl/server.pem
  --tlsCAFile /etc/mongo/ssl/ca.crt
  --tlsAllowConnectionsWithoutCertificates
  --bind_ip_all  # ← This is critical!
```

### 4. Network Connectivity Issues

**Test from primary server:**
```bash
# On primary server
ping -c 3 192.168.2.6
telnet 192.168.2.6 27017
# Or
nc -zv 192.168.2.6 27017
```

**Fix:** Ensure network routing is correct and servers can reach each other.

### 5. TLS Certificate Issues

**Check:**
```bash
# On new server
ls -la tls-certs/
# Should have: ca.crt, server.pem, client.pem, keyfile
```

**Fix:** Ensure all TLS certificates are copied correctly from other nodes.

### 6. keyFile Mismatch

**Check:**
```bash
# Compare keyFiles on all servers (should match exactly)
md5sum tls-certs/keyfile  # On primary
md5sum tls-certs/keyfile  # On secondary-1
md5sum tls-certs/keyfile  # On new secondary-2 (should match!)
```

**Fix:** Copy the keyFile from a working node:
```bash
# From primary server
scp ~/ha-mongodb/tls-certs/keyfile user@192.168.2.6:~/ha-mongodb/tls-certs/keyfile
```

### 7. Container Not on Same Network

**Check:**
```bash
# On new server
docker network ls
docker network inspect ha-mongodb_db-network 2>/dev/null || echo "Network not found"
```

**Fix:** Create the network if needed:
```bash
docker network create ha-mongodb_db-network
```

**Note:** For separate servers, network names don't need to match - use IP addresses instead.

### 8. Replica Set Configuration Issue

**Check current configuration:**
```bash
# On primary server
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.conf()"
```

**Fix:** If the member was added incorrectly, remove and re-add:
```bash
# Remove
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.remove('192.168.2.6:27017')"

# Wait a few seconds
sleep 5

# Re-add with correct configuration
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.add({ _id: 2, host: '192.168.2.6:27017', priority: 1 })"
```

## Diagnostic Script

Run this on your **primary server**:

```bash
cd ~/ha-mongodb
./scripts/diagnose-secondary-connectivity.sh 192.168.2.6
```

This will check:
- Network connectivity
- Port accessibility
- MongoDB connection
- Replica set member status

## Step-by-Step Fix

### Step 1: Verify Container is Running

On **new server** (192.168.2.6):

```bash
docker ps | grep mongo-secondary-2
docker logs mongo-secondary-2 | tail -50
```

### Step 2: Check Firewall

On **new server**:

```bash
# Check firewall status
sudo ufw status

# Allow MongoDB port from other servers
sudo ufw allow from 192.168.2.1 to any port 27017  # Adjust IPs
sudo ufw allow from 192.168.2.2 to any port 27017
```

### Step 3: Verify MongoDB is Listening

On **new server**:

```bash
# Check if MongoDB is listening on all interfaces
docker exec mongo-secondary-2 netstat -tlnp | grep 27017

# Should show: 0.0.0.0:27017
# If it shows 127.0.0.1:27017, MongoDB is only listening on localhost
```

### Step 4: Test Connectivity from Primary

On **primary server**:

```bash
# Test network connectivity
ping -c 3 192.168.2.6

# Test port accessibility
telnet 192.168.2.6 27017
# Or
nc -zv 192.168.2.6 27017
```

### Step 5: Check Replica Set Status

On **primary server**:

```bash
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status()"
```

Look for error messages in the member's status.

## Most Common Fix

The most common issue is **firewall blocking port 27017**. 

On the **new server** (192.168.2.6):

```bash
# Allow MongoDB port from other MongoDB servers
sudo ufw allow from 192.168.2.1 to any port 27017  # Primary
sudo ufw allow from 192.168.2.2 to any port 27017  # Secondary-1

# Verify
sudo ufw status | grep 27017
```

Then wait 30-60 seconds and check replica set status again.

## Summary

1. ✅ Container running on new server
2. ✅ Firewall allows port 27017 from other servers
3. ✅ MongoDB bound to 0.0.0.0 (all interfaces)
4. ✅ Network connectivity between servers
5. ✅ keyFile matches on all nodes
6. ✅ TLS certificates present

Run the diagnostic script to identify which of these is the issue!
