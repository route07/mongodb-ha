# Quick Deployment Guide

Fast deployment steps for remote server.

## Prerequisites Check

```bash
# Verify Docker is installed
docker --version
docker-compose --version

# If not installed, run:
curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

## Deployment Steps

### 1. Transfer Files

```bash
# On remote server
cd ~
git clone <your-repo> ha-mongodb
cd ha-mongodb
```

### 2. Configure

```bash
# Copy and edit .env
cp .env.example .env
nano .env  # Set MONGO_INITDB_ROOT_USERNAME and MONGO_INITDB_ROOT_PASSWORD
```

### 3. Generate Certificates

```bash
./scripts/generate-tls-certs.sh
./scripts/generate-keyfile.sh
```

### 4. Start Services

```bash
docker-compose up -d
```

### 5. Wait and Verify

```bash
# Wait 60 seconds for initialization
sleep 60

# Check status
docker-compose ps

# Check replica set
source .env
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status()"
```

### 6. Access Admin UI

Open: `http://YOUR_SERVER_IP:3000`

## If Issues Occur

### User Not Found
```bash
./scripts/fix-user-quick.sh
```

### Replica Set Not Initialized
```bash
./scripts/init-replica-set-manual.sh
```

### Complete Reset
```bash
docker-compose down
rm -rf db_data_primary/ db_data_secondary1/ db_data_secondary2/
docker-compose up -d
```

## Firewall (if needed)

```bash
sudo ufw allow 3000/tcp  # Admin UI
sudo ufw allow 27017/tcp # MongoDB (optional, use SSH tunnel instead)
```

## That's It!

Your MongoDB HA replica set should now be running. See [DEPLOYMENT.md](./docs/DEPLOYMENT.md) for detailed instructions.
