# HA Setup Quick Start

Quick reference for setting up High Availability MongoDB replica set.

## Prerequisites Checklist

- [ ] Backup existing data (if migrating)
- [ ] Sufficient resources (3x single node)
- [ ] Docker and Docker Compose installed

## Setup Steps

### 1. Generate TLS Certificates and KeyFile
```bash
# Generate TLS certificates (includes replica set hostnames)
./scripts/generate-tls-certs.sh

# Generate keyFile for replica set authentication
./scripts/generate-keyfile.sh
```

### 2. Configure Environment
Add to `.env`:
```bash
REPLICA_SET_NAME=rs0
```

### 3. Start HA Services
```bash
docker-compose -f docker-compose.ha.yaml up -d --build
```

### 4. Verify Setup
```bash
# Check all services are running
docker-compose -f docker-compose.ha.yaml ps

# Check replica set status
docker exec -it mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status()"
```

## Connection String

```bash
mongodb://username:password@localhost:27017/?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

## Files Created

- `docker-compose.ha.yaml` - HA docker-compose configuration
- `scripts/init-replica-set.sh` - Replica set initialization script
- `scripts/healthcheck-replica-set.sh` - Enhanced healthcheck
- `docs/HA_SETUP.md` - Complete HA documentation

## Troubleshooting

**Replica set not initializing?**
```bash
docker-compose -f docker-compose.ha.yaml logs mongodb-init
```

**Check node health:**
```bash
docker-compose -f docker-compose.ha.yaml ps
```

**Manual initialization:**
```bash
docker exec -it mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.initiate()"
```

## See Also

- [Complete HA Setup Guide](./docs/HA_SETUP.md) - Full documentation
- [TLS Setup Guide](./docs/TLS_SETUP.md) - TLS configuration details
