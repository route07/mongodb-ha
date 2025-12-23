# Moving Secondary Node to Another Server

## Overview

This guide explains how to move `mongodb-secondary-2` from the current server to a new server while maintaining the replica set.

## Prerequisites

- New server has Docker and Docker Compose installed
- Network connectivity between servers (MongoDB port 27017 accessible)
- TLS certificates and keyFile available on new server
- Same MongoDB version (7.0) on new server

## Step-by-Step Process

### Step 1: Remove Secondary-2 from Current Replica Set

On your **current MongoDB server**:

```bash
cd ~/ha-mongodb
source .env

# Connect to primary
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
    // Remove secondary-2
    rs.remove('mongodb-secondary-2:27017');
    print('Removed mongodb-secondary-2 from replica set');
  "
```

Wait for the removal to complete (usually 10-20 seconds).

### Step 2: Stop and Remove Secondary-2 Container

```bash
# Stop the container
docker-compose stop mongodb-secondary-2

# Optional: Remove container (keeps data)
docker-compose rm -f mongodb-secondary-2
```

### Step 3: Prepare New Server

On your **new server**:

#### 3.1: Clone/Copy MongoDB Setup

```bash
# Option A: Clone the repository
git clone <your-repo-url> ~/ha-mongodb
cd ~/ha-mongodb

# Option B: Copy files from old server
# On old server:
# scp -r ~/ha-mongodb user@new-server:~/ha-mongodb
```

#### 3.2: Copy Required Files

You need these files on the new server:

```bash
# TLS certificates
tls-certs/
  ├── ca.crt
  ├── server.pem
  ├── client.pem
  └── keyfile          # Important: Must be identical to other nodes

# Environment file
.env                   # With same credentials

# Docker Compose file
docker-compose.yaml
```

**Critical**: The `keyfile` must be **identical** on all nodes. Copy it securely:

```bash
# From old server
scp ~/ha-mongodb/tls-certs/keyfile user@new-server:~/ha-mongodb/tls-certs/keyfile

# Verify it's identical
md5sum ~/ha-mongodb/tls-certs/keyfile  # On old server
md5sum ~/ha-mongodb/tls-certs/keyfile  # On new server (should match)
```

#### 3.3: Update docker-compose.yaml

On the **new server**, modify `docker-compose.yaml` to only run `mongodb-secondary-2`:

**Option A: Create a separate docker-compose file**

Create `docker-compose-secondary2.yaml`:

```yaml
version: '3.8'

services:
  mongodb-secondary-2:
    image: mongo:7.0
    container_name: mongo-secondary-2
    restart: unless-stopped
    environment:
      MONGO_INITDB_ROOT_USERNAME: ${MONGO_INITDB_ROOT_USERNAME}
      MONGO_INITDB_ROOT_PASSWORD: ${MONGO_INITDB_ROOT_PASSWORD}
    volumes:
      - ./db_data_secondary2:/data/db
      - ./tls-certs:/etc/mongo/ssl:ro
      - ./scripts:/scripts:ro
    entrypoint: ["bash", "/scripts/fix-keyfile-permissions.sh"]
    command: >
      mongod
      --replSet ${REPLICA_SET_NAME:-rs0}
      --keyFile /etc/mongo/ssl/keyfile
      --tlsMode requireTLS
      --tlsCertificateKeyFile /etc/mongo/ssl/server.pem
      --tlsCAFile /etc/mongo/ssl/ca.crt
      --tlsAllowConnectionsWithoutCertificates
      --bind_ip_all
    networks:
      - db-network

networks:
  db-network:
    external: true
    name: ha-mongodb_db-network
```

**Option B: Comment out other services in main docker-compose.yaml**

Comment out `mongodb-primary` and `mongodb-secondary-1` services.

#### 3.4: Create Docker Network (if needed)

```bash
# Check if network exists
docker network ls | grep ha-mongodb_db-network

# If not, create it (must match name from other servers)
docker network create ha-mongodb_db-network
```

**Important**: Network name must match across all servers if you want them to communicate via Docker network names.

### Step 4: Configure Network Connectivity

#### Option A: Same Network (Docker Swarm/Overlay)

If using Docker Swarm or overlay network, nodes can communicate via service names.

#### Option B: Different Networks (Recommended for Separate Servers)

Use IP addresses or hostnames instead of Docker service names.

**On new server**, update the replica set configuration to use the server's IP or hostname:

```bash
# Get new server's IP
hostname -I | awk '{print $1}'
# Or use a hostname that resolves to this server
```

### Step 5: Start Secondary-2 on New Server

```bash
cd ~/ha-mongodb

# Start only secondary-2
docker-compose -f docker-compose-secondary2.yaml up -d mongodb-secondary-2

# Or if using main docker-compose.yaml with other services commented
docker-compose up -d mongodb-secondary-2

# Check it's running
docker-compose ps
docker logs mongo-secondary-2
```

### Step 6: Add Secondary-2 Back to Replica Set

On your **primary server** (or any server with access to primary):

```bash
cd ~/ha-mongodb
source .env

# Get new server's IP or hostname
NEW_SERVER_IP="192.168.2.6"  # Replace with actual IP
# Or use hostname if DNS is configured
NEW_SERVER_HOST="ts-db-1"

# Add secondary-2 with new hostname/IP
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
    // Add with new hostname/IP
    rs.add({
      _id: 2,
      host: '$NEW_SERVER_IP:27017',
      priority: 1
    });
    print('Added mongodb-secondary-2 at ' + '$NEW_SERVER_IP:27017');
  "
```

**Important**: Use the IP address or hostname that other nodes can reach, not Docker service names.

### Step 7: Verify Replica Set Status

```bash
# On primary server
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status()"
```

You should see:
- `mongodb-primary:27017` - PRIMARY
- `mongodb-secondary-1:27017` - SECONDARY
- `192.168.10.3:27017` (or your new hostname) - SECONDARY (syncing)

### Step 8: Wait for Initial Sync

The secondary will need to sync data. Monitor progress:

```bash
# Check replication lag
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
    var status = rs.status();
    status.members.forEach(function(m) {
      if (m.stateStr === 'SECONDARY') {
        print(m.name + ': ' + m.stateStr);
        if (m.optimeDate) {
          var lag = new Date() - m.optimeDate;
          print('  Replication lag: ' + Math.round(lag/1000) + ' seconds');
        }
      }
    });
  "
```

Wait until replication lag is minimal (< 10 seconds).

## Network Configuration Options

### Option 1: Use IP Addresses (Simplest)

Use server IP addresses in replica set configuration:

```javascript
rs.add({ _id: 2, host: '192.168.10.3:27017', priority: 1 });
```

**Pros**: Simple, works immediately  
**Cons**: IPs might change, less readable

### Option 2: Use Hostnames with DNS

Configure DNS so hostnames resolve:

```javascript
rs.add({ _id: 2, host: 'mongodb-secondary-2-new.example.com:27017', priority: 1 });
```

**Pros**: More maintainable  
**Cons**: Requires DNS configuration

### Option 3: Use /etc/hosts on Each Server

Add hostname mappings to `/etc/hosts` on each server:

```bash
# On primary server
echo "192.168.10.3 mongodb-secondary-2-new" | sudo tee -a /etc/hosts

# On secondary-1 server
echo "192.168.10.3 mongodb-secondary-2-new" | sudo tee -a /etc/hosts

# On new secondary-2 server
echo "192.168.10.1 mongodb-primary" | sudo tee -a /etc/hosts
echo "192.168.10.2 mongodb-secondary-1" | sudo tee -a /etc/hosts
```

Then use hostnames in replica set:

```javascript
rs.add({ _id: 2, host: 'mongodb-secondary-2-new:27017', priority: 1 });
```

## Firewall Configuration

Ensure MongoDB port is accessible between servers:

```bash
# On new server
sudo ufw allow from 192.168.10.1 to any port 27017  # Primary
sudo ufw allow from 192.168.10.2 to any port 27017  # Secondary-1

# On primary/secondary-1 servers
sudo ufw allow from 192.168.10.3 to any port 27017  # New Secondary-2
```

## Troubleshooting

### Issue: Secondary Can't Connect to Primary

**Symptom**: Secondary shows as DOWN or UNREACHABLE

**Check**:
1. Network connectivity: `ping <primary-ip>`
2. Port accessibility: `telnet <primary-ip> 27017`
3. Firewall rules
4. TLS certificates match
5. keyFile is identical

### Issue: Replication Not Starting

**Symptom**: Secondary stays in STARTUP2 state

**Fix**: Check logs on secondary:
```bash
docker logs mongo-secondary-2 | tail -50
```

Common causes:
- Network issues
- TLS certificate problems
- keyFile mismatch
- Insufficient disk space

### Issue: Authentication Failed

**Symptom**: "Authentication failed" errors

**Fix**: Verify keyFile is identical:
```bash
# Compare keyFiles
md5sum tls-certs/keyfile  # On each server (should match)
```

## Summary

1. ✅ Remove secondary-2 from replica set
2. ✅ Stop container on old server
3. ✅ Copy files to new server (especially keyFile!)
4. ✅ Configure network connectivity
5. ✅ Start secondary-2 on new server
6. ✅ Add back to replica set with new IP/hostname
7. ✅ Verify and wait for sync

**Key Points**:
- keyFile must be identical on all nodes
- Use IP addresses or resolvable hostnames (not Docker service names)
- Ensure network connectivity and firewall rules
- Wait for initial sync to complete
