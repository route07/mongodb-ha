# Remote Server Deployment Guide

Complete guide for deploying the MongoDB HA Replica Set on a remote server.

## Prerequisites

### On Your Local Machine
- Git installed
- SSH access to remote server
- Basic knowledge of Linux commands

### On Remote Server
- Ubuntu/Debian Linux (or similar)
- Docker and Docker Compose installed
- At least 4GB RAM (8GB+ recommended)
- At least 20GB free disk space
- Open ports: 27017 (MongoDB), 3000 (Admin UI) - or configure firewall

## Step 1: Prepare Remote Server

### Install Docker and Docker Compose

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to docker group (optional, to run without sudo)
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Verify installation
docker --version
docker-compose --version
```

### Create Project Directory

```bash
# Create directory
mkdir -p ~/ha-mongodb
cd ~/ha-mongodb
```

## Step 2: Transfer Files to Remote Server

### Option 1: Using Git (Recommended)

```bash
# On remote server
cd ~/ha-mongodb
git clone <your-repo-url> .

# Or if you have the files locally, push to a repo first
```

### Option 2: Using SCP

```bash
# From your local machine
scp -r /path/to/ha-mongodb/* user@remote-server:~/ha-mongodb/
```

### Option 3: Using rsync

```bash
# From your local machine
rsync -avz --exclude 'db_data*' --exclude '.git' \
  /path/to/ha-mongodb/ user@remote-server:~/ha-mongodb/
```

## Step 3: Configure Environment

```bash
# On remote server
cd ~/ha-mongodb

# Copy example env file
cp .env.example .env

# Edit with your preferred editor
nano .env
# or
vi .env
```

### Required Environment Variables

```bash
# MongoDB credentials (REQUIRED)
MONGO_INITDB_ROOT_USERNAME=your_username
MONGO_INITDB_ROOT_PASSWORD=your_secure_password

# Replica Set Configuration
REPLICA_SET_NAME=rs0

# Ports
MONGO_PORT=27017
ADMIN_UI_PORT=3000

# Optional: Web3 Auth
WEB3_AUTH_ENABLED=false
ADMIN_WALLETS=
SESSION_SECRET=your-secret-key-here
```

**Important**: Use a strong password for production!

## Step 4: Generate TLS Certificates and KeyFile

```bash
cd ~/ha-mongodb

# Generate TLS certificates (includes replica set hostnames)
./scripts/generate-tls-certs.sh

# Generate keyFile for replica set authentication
./scripts/generate-keyfile.sh
```

**Note**: The certificates are self-signed. For production, consider using certificates from a trusted CA.

## Step 5: Configure Firewall (if applicable)

```bash
# Allow MongoDB port (if exposing externally)
sudo ufw allow 27017/tcp

# Allow Admin UI port
sudo ufw allow 3000/tcp

# Or use specific IP restrictions
sudo ufw allow from YOUR_IP to any port 27017
sudo ufw allow from YOUR_IP to any port 3000

# Enable firewall
sudo ufw enable
```

**Security Note**: For production, consider:
- Not exposing MongoDB port externally
- Using SSH tunnel for MongoDB access
- Restricting Admin UI to specific IPs
- Using a reverse proxy (nginx) with SSL for Admin UI

## Step 6: Start Services

### First Time Setup

```bash
cd ~/ha-mongodb

# Start all services
docker-compose up -d

# Watch logs (optional)
docker-compose logs -f
```

### Wait for Initialization

The first startup takes 60-90 seconds:
1. MongoDB containers start
2. Root user is created automatically (if data directory is empty)
3. Replica set initializes
4. mongo-admin connects

### Verify Everything is Running

```bash
# Check container status
docker-compose ps

# Check replica set status
source .env
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status()"

# Check mongo-admin logs
docker-compose logs mongo-admin | tail -20
```

## Step 7: Access Services

### Admin UI

Open in browser:
```
http://YOUR_SERVER_IP:3000
```

You should see:
- Connection status: Connected
- Cluster status showing 3 nodes (Primary + 2 Secondaries)
- Database list

### MongoDB Connection

From your local machine (if port is exposed):
```bash
mongosh "mongodb://username:password@YOUR_SERVER_IP:27017/?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

Or use SSH tunnel (more secure):
```bash
# Create SSH tunnel
ssh -L 27017:localhost:27017 user@YOUR_SERVER_IP

# Then connect locally
mongosh "mongodb://username:password@localhost:27017/?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
```

## Step 8: Enable keyFile (Optional but Recommended)

After confirming everything works, you can re-enable keyFile for better security:

```bash
# Edit docker-compose.yaml
nano docker-compose.yaml

# Uncomment --keyFile lines in all three MongoDB services:
#   mongodb-primary
#   mongodb-secondary-1  
#   mongodb-secondary-2

# Restart services
docker-compose restart
```

**Note**: keyFile requires the user to exist. If you get authentication errors after enabling it, see troubleshooting section.

## Common Remote Server Issues

### Issue: User Not Found Error

**Symptom**: `UserNotFound: Could not find user "username"`

**Cause**: Data directory exists but user wasn't created

**Solution**:
```bash
# Option 1: Fresh start (if you can lose data)
docker-compose down
rm -rf db_data_primary/ db_data_secondary1/ db_data_secondary2/
docker-compose up -d

# Option 2: Create user manually
./scripts/fix-user-quick.sh
```

### Issue: Replica Set Not Initializing

**Symptom**: Oplog warnings, no primary elected

**Solution**:
```bash
# Initialize manually
./scripts/init-replica-set-manual.sh
```

### Issue: Can't Connect from Remote

**Check**:
1. Firewall allows port 27017/3000
2. MongoDB is bound to `0.0.0.0` (not just localhost)
3. Network security groups (if using cloud)

**Test**:
```bash
# From remote server
curl http://localhost:3000/api/health

# From your machine
telnet YOUR_SERVER_IP 3000
```

### Issue: Out of Disk Space

**Check**:
```bash
df -h
```

**Clean up** (if needed):
```bash
# Remove old containers/images
docker system prune -a

# Check MongoDB data size
du -sh db_data_primary/ db_data_secondary1/ db_data_secondary2/
```

### Issue: Permission Denied

**Fix**:
```bash
# Fix ownership
sudo chown -R $USER:$USER ~/ha-mongodb

# Fix script permissions
chmod +x scripts/*.sh
```

## Maintenance Commands

### Stop Services
```bash
docker-compose down
```

### Start Services
```bash
docker-compose up -d
```

### Restart Services
```bash
docker-compose restart
```

### View Logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f mongodb-primary
docker-compose logs -f mongo-admin
```

### Update Services
```bash
# Pull latest images
docker-compose pull

# Rebuild mongo-admin (if code changed)
docker-compose build mongo-admin

# Restart
docker-compose up -d
```

### Backup Database
```bash
source .env
docker exec mongo-primary mongodump --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --out /data/backup

# Copy backup from container
docker cp mongo-primary:/data/backup ./backup-$(date +%Y%m%d)
```

## Security Best Practices

1. **Use Strong Passwords**: Generate secure passwords for MongoDB
2. **Restrict Network Access**: Use firewall rules to limit access
3. **Enable keyFile**: Re-enable after initial setup
4. **Use SSH Tunnels**: For remote MongoDB access instead of exposing port
5. **Regular Backups**: Set up automated backups
6. **Monitor Logs**: Regularly check for suspicious activity
7. **Keep Updated**: Regularly update Docker images and system packages
8. **Use Reverse Proxy**: For Admin UI with SSL (nginx/traefik)

## Production Checklist

- [ ] Strong passwords set in `.env`
- [ ] TLS certificates generated
- [ ] keyFile generated and configured
- [ ] Firewall configured
- [ ] MongoDB port not exposed publicly (or restricted)
- [ ] Admin UI behind reverse proxy with SSL
- [ ] Backup strategy in place
- [ ] Monitoring set up
- [ ] Log rotation configured
- [ ] Resource limits set in docker-compose.yaml

## Troubleshooting

### Check Service Status
```bash
docker-compose ps
docker-compose logs --tail=50
```

### Test MongoDB Connection
```bash
source .env
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "db.adminCommand('ping')"
```

### Check Replica Set
```bash
source .env
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status()"
```

### Reset Everything (⚠️ Deletes All Data)
```bash
docker-compose down
rm -rf db_data_primary/ db_data_secondary1/ db_data_secondary2/
docker-compose up -d
```

## Quick Reference

```bash
# Start
docker-compose up -d

# Stop
docker-compose down

# Restart
docker-compose restart

# Logs
docker-compose logs -f

# Status
docker-compose ps

# Replica set status
source .env && docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin --eval "rs.status()"
```

## Support

For issues:
1. Check logs: `docker-compose logs`
2. Review [Troubleshooting Guide](./TROUBLESHOOTING.md)
3. Check [HA Setup Guide](./HA_SETUP.md)

## Next Steps

After deployment:
1. Set up automated backups
2. Configure monitoring/alerting
3. Set up log rotation
4. Configure reverse proxy for Admin UI
5. Document connection strings for your applications
