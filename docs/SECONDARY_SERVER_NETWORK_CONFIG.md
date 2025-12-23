# Network Configuration for Secondary Server

## Overview

For the **second server** (where secondary-2 runs), the network configuration is **independent** from the primary server. Since nodes communicate via IP addresses, the network names don't need to match.

## Option 1: Same Network Name (Recommended for Consistency)

Use the same network name for consistency and easier management:

```yaml
# docker-compose.yaml on secondary server
services:
  mongodb-secondary-2:
    # ... other config ...
    networks:
      - db-network

networks:
  db-network:
    driver: bridge
    # Same name as primary server (optional but recommended)
```

**Benefits:**
- ✅ Consistent configuration across servers
- ✅ Easier to manage (same setup everywhere)
- ✅ If you run mongo-admin on this server, it can use the same network

## Option 2: Different Network Name (Also Fine)

You can use a different network name - it doesn't matter:

```yaml
# docker-compose.yaml on secondary server
networks:
  mongodb-network:  # Different name - still works!
    driver: bridge
```

**Why this works:**
- Nodes communicate via IP addresses (`192.168.2.6:27017`)
- Docker network is only for local containers on that server
- Network name doesn't affect inter-server communication

## Recommended Configuration

**For the secondary server, use the same configuration:**

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
    healthcheck:
      test: ["CMD", "bash", "/scripts/healthcheck.sh"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 40s

networks:
  db-network:
    driver: bridge
    # Internal network - name can match or be different
    # Doesn't affect inter-server communication
```

## Key Points

### 1. Network Type: Internal (Not External)

```yaml
networks:
  db-network:
    driver: bridge
    # NOT external: true
    # Internal network is fine
```

**Why:**
- Each server has its own isolated network
- Nodes communicate via IP addresses, not Docker service names
- No need for external/overlay network

### 2. Network Name: Can Match or Differ

**Option A: Same name (recommended)**
```yaml
networks:
  db-network:  # Same as primary server
    driver: bridge
```

**Option B: Different name (also fine)**
```yaml
networks:
  mongodb-network:  # Different name - still works!
    driver: bridge
```

Both work because nodes use IP addresses, not service names.

### 3. No External Network Needed

**Don't do this** (unless using Docker Swarm):
```yaml
networks:
  db-network:
    external: true  # ❌ Not needed for separate servers
    name: mongodb-cluster-network
```

**Why not:**
- External networks are for Docker Swarm/overlay
- Your nodes are on separate servers using IP addresses
- Internal network is sufficient

## Complete docker-compose.yaml for Secondary Server

Here's a complete example for the secondary server:

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
    healthcheck:
      test: ["CMD", "bash", "/scripts/healthcheck.sh"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 40s

networks:
  db-network:
    driver: bridge
    # Internal network - same as primary server (for consistency)
```

## Summary

**For the second server:**

- ✅ **Use internal network** (`driver: bridge`)
- ✅ **Same network name** as primary server (recommended for consistency)
- ✅ **NOT external** (unless using Docker Swarm)
- ✅ **Network name doesn't affect** inter-server communication (nodes use IPs)

**The network configuration is independent per server** - each server can have its own network, but using the same name makes management easier.
