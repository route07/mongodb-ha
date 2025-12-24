# MongoDB Docker Setup

A simple Docker Compose setup for MongoDB with TLS encryption and Mongo Express admin UI.

## Prerequisites

- Docker and Docker Compose installed
- OpenSSL (for generating TLS certificates)

## Quick Start

### 1. Generate TLS Certificates

```bash
./generate-tls-certs.sh
```

This creates the required TLS certificates in the `tls-certs/` directory.

### 2. Configure Environment Variables

Edit the `.env` file with your desired credentials:

```bash
# Mongo DB
MONGO_INITDB_ROOT_USERNAME=dbUser
MONGO_INITDB_ROOT_PASSWORD=your_password_here
MONGO_PORT=27017

# Custom MongoDB Admin UI (recommended - supports TLS)
ADMIN_UI_PORT=3000

# Web3 Authentication. Add one or more admin wallets
WEB3_AUTH_ENABLED=false
ADMIN_WALLETS=0x9220160e87D7995bC551a109C61505d60C9eC33B,0x97a362bC0d128E008E2E2eD7Fc10CFDdDF54ed55
SESSION_SECRET=change-this-secret-in-production
```

### 3. Start Services

For the first time (or after changes to mongo-admin), build and start:

```bash
docker-compose up -d --build
```

For subsequent starts (no code changes):

```bash
docker-compose up -d
```

### 4. Access Services

- **MongoDB**: `localhost:27017` (requires TLS)
- **Custom Admin UI** (with TLS support): `http://localhost:3000`
  - Full TLS support
  - Web3 wallet authentication (optional, see Web3 Auth section)
  - Database export/import
  - Create/delete databases
- **Mongo Express UI** (legacy): `http://localhost:8992`

## Connection String

Connect to MongoDB using TLS:

```bash
mongosh "mongodb://your_username:your_password@localhost:27017/?tls=true&tlsCAFile=./tls-certs/ca.crt"
```

## Services

- **mongodb**: MongoDB 7.0 instance with TLS encryption (requireTLS mode)
- **mongo-admin**: Custom web-based MongoDB admin interface with full TLS support
- **mongo-express**: Legacy MongoDB admin interface (mongo-express)

## Remote Server Deployment

**Quick Start**: See [DEPLOY_QUICK.md](./DEPLOY_QUICK.md) for fast deployment steps.

**Complete Guide**: See [docs/DEPLOYMENT.md](./docs/DEPLOYMENT.md) for detailed remote server deployment instructions.

## High Availability (Replica Set) Setup

This setup also supports a **3-node replica set** for High Availability with automatic failover.

### Quick Start for HA

1. **Regenerate TLS certificates** (includes replica set hostnames):
   ```bash
   ./scripts/generate-tls-certs.sh
   ```

2. **Configure environment** (add to `.env`):
   ```bash
   REPLICA_SET_NAME=rs0
   ```

3. **Start HA services**:
   ```bash
   docker-compose -f docker-compose.ha.yaml up -d --build
   ```

This will start:
- 3 MongoDB nodes (1 primary + 2 secondaries)
- Automatic replica set initialization
- Admin UI with replica set support

### HA Features

- ✅ Automatic failover (primary → secondary)
- ✅ Data redundancy (3 copies)
- ✅ Read scaling (read from secondaries)
- ✅ Zero-downtime maintenance
- ✅ All nodes exposed (secondary ports: 27018, 27019) - ensures clients can connect even after failover

### Connection String for HA

**Recommended** (with all members - MongoDB driver will automatically discover and connect to primary):
```bash
mongosh "mongodb://username:password@localhost:27017,localhost:27018,localhost:27019/?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

**Alternative** (single entry point - driver will discover other members):
```bash
mongosh "mongodb://username:password@localhost:27017/?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

**Note**: Secondary ports (27018, 27019) are exposed so clients can:
1. Connect directly if a secondary becomes primary during failover
2. Read from secondaries for load distribution (see [Secondary Reads Guide](./docs/SECONDARY_READS.md))
3. The MongoDB driver's automatic discovery will handle primary changes, but having all ports exposed ensures connectivity even if discovery fails.

**Important**: 
- Clients can **read** from secondaries (with `readPreference`), but **writes** can only go to the primary. See [SECONDARY_READS.md](./docs/SECONDARY_READS.md) for details.
- Clients **must use the same CA certificate** (`ca.crt`) as the server. See [TLS_CA_CERTIFICATE.md](./docs/TLS_CA_CERTIFICATE.md) for details.

**See [HA_SETUP.md](./docs/HA_SETUP.md) for complete HA setup guide, migration instructions, and troubleshooting.**

## Troubleshooting: Primary Node Fails on First Start

If you're starting a new MongoDB HA setup and the primary node fails with errors like:

```
NamespaceNotFound: Collection [local.oplog.rs] not found
ReadConcernMajorityNotAvailableYet: Read concern majority reads are currently not possible
UserNotFound: Could not find user "your_username" for db "admin"
```

This is a **chicken-and-egg problem**: MongoDB is in replica set mode but not initialized, so it won't accept writes (including user creation), but the initialization script needs authentication.

### Quick Fix

1. **Initialize the replica set first** (works without authentication):
   ```bash
   source .env
   docker exec mongo-primary mongosh --tls \
     --tlsAllowInvalidCertificates \
     --tlsCAFile /etc/mongo/ssl/ca.crt \
     --eval "rs.initiate({_id: '${REPLICA_SET_NAME:-rs0}', members: [{_id: 0, host: 'mongodb-primary:27017'}]})"
   ```

2. **Wait for primary election** (10 seconds):
   ```bash
   sleep 10
   docker exec mongo-primary mongosh --tls \
     --tlsAllowInvalidCertificates \
     --tlsCAFile /etc/mongo/ssl/ca.crt \
     --eval "rs.isMaster().ismaster"
   ```
   Should return: `true`

3. **Create the root user**:
   ```bash
   docker exec mongo-primary mongosh --tls \
     --tlsAllowInvalidCertificates \
     --tlsCAFile /etc/mongo/ssl/ca.crt \
     --eval "db.getSiblingDB('admin').createUser({user: '${MONGO_INITDB_ROOT_USERNAME}', pwd: '${MONGO_INITDB_ROOT_PASSWORD}', roles: [{ role: 'root', db: 'admin' }]})"
   ```

4. **Start and add secondary nodes**:
   ```bash
   docker-compose up -d mongodb-secondary-1 mongodb-secondary-2
   sleep 15
   
   docker exec mongo-primary mongosh --tls \
     --tlsAllowInvalidCertificates \
     --tlsCAFile /etc/mongo/ssl/ca.crt \
     -u "${MONGO_INITDB_ROOT_USERNAME}" \
     -p "${MONGO_INITDB_ROOT_PASSWORD}" \
     --authenticationDatabase admin \
     --eval "rs.add('mongodb-secondary-1:27017'); rs.add('mongodb-secondary-2:27017')"
   ```

5. **Verify everything is working**:
   ```bash
   docker-compose ps  # All should be healthy
   docker exec mongo-primary mongosh --tls \
     --tlsAllowInvalidCertificates \
     --tlsCAFile /etc/mongo/ssl/ca.crt \
     -u "${MONGO_INITDB_ROOT_USERNAME}" \
     -p "${MONGO_INITDB_ROOT_PASSWORD}" \
     --authenticationDatabase admin \
     --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"
   ```

**Expected result**: All nodes should show as `PRIMARY` or `SECONDARY` with health status `1`, and the oplog warnings will disappear.

**Want to test failover?** See [TEST_FAILOVER.md](./docs/TEST_FAILOVER.md) for step-by-step instructions on testing automatic failover.

**Having issues?** Check the [Troubleshooting Guide](./docs/TROUBLESHOOTING.md) for more common problems and solutions.

## Stop Services

```bash
docker-compose down
```

To remove volumes (database data):

```bash
docker-compose down -v
```

## Mongo Admin UI Setup

The custom MongoDB Admin UI (`mongo-admin`) needs to be built on first run:

```bash
# Build and start all services (first time)
docker-compose up -d --build 
(or just docker-compose up -d , it will build if not built. If any changes, use --build)

# Or build only mongo-admin
docker-compose build mongo-admin
docker-compose up -d mongo-admin
```

### Web3 Authentication (Optional)

The admin UI supports Web3 wallet authentication. To enable:

1. Edit `.env` file:
   ```bash
   WEB3_AUTH_ENABLED=true
   ADMIN_WALLETS=0xYourWalletAddress1,0xYourWalletAddress2
   SESSION_SECRET=your-secure-random-secret
   ```

2. Restart the service:
   ```bash
   docker-compose restart mongo-admin
   ```

3. Connect your wallet when accessing the UI

See `mongo-admin/WEB3_AUTH.md` for detailed authentication setup.

## Export/Import Databases

To migrate databases from an old MongoDB server to the new admin UI:

### Quick Method (Using Export Tool)

The export tool is in the `database-export/` directory. **This is optional** - only install if you need to export from other MongoDB servers.

```bash
# Navigate to export tool directory
cd database-export

# Install dependencies (one time, only if you need this tool)
npm install

# Export from old server
# Basic (no TLS)
node export-database.js "mongodb://user:pass@old-server:27017/dbname"

# With TLS (like your new server)
node export-database.js "mongodb://user:pass@old-server:27017/dbname?tls=true&tlsCAFile=../tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"

# This creates: dbname_export_TIMESTAMP.json
# Then import via Admin UI at http://localhost:3000
```

See [database-export/README.md](./database-export/README.md) for complete export tool documentation.

### Manual Methods

1. **Using mongoexport** (per collection):
   ```bash
   mongoexport --uri="mongodb://user:pass@old-server:27017/dbname" \
     --collection=collection_name --out=collection.json --jsonArray
   ```

2. **Using mongodump** (entire database):
   ```bash
   mongodump --uri="mongodb://user:pass@old-server:27017/dbname" --out=./backup
   # Then convert BSON to JSON (see guide below)
   ```

3. **Import via Admin UI**:
   - Go to `http://localhost:3000`
   - Create the database (if needed)
   - Click "Import" on the database
   - Select your JSON file
   - Import!

See [EXPORT_IMPORT_GUIDE.md](./docs/EXPORT_IMPORT_GUIDE.md) for detailed instructions and troubleshooting.

## Notes

- TLS certificates are stored in `tls-certs/` directory
- Database data is persisted in `db_data/` directory
- All configuration values are managed via `.env` file
- Mongo Admin UI requires initial build with `--build` flag
