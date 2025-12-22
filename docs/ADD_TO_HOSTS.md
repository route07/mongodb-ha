# Add MongoDB Hostnames to /etc/hosts

## Quick Method

Run this command (requires sudo):

```bash
sudo sh -c 'echo "127.0.0.1 mongodb-primary mongodb-secondary-1 mongodb-secondary-2" >> /etc/hosts'
```

## Or Use the Script

```bash
cd ~/ha-mongodb
sudo ./scripts/add-mongodb-hosts.sh
```

## Verify It Works

```bash
# Test hostname resolution
ping -c 1 mongodb-primary
ping -c 1 mongodb-secondary-1
ping -c 1 mongodb-secondary-2

# Should all resolve to 127.0.0.1
```

## Update Your Connection String

Now you can add `replicaSet=rs0` back to your `.env.local`:

```bash
MONGODB_URI=mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin
```

## Restart Your App

After updating `.env.local`, restart your application:

```bash
# Stop your dev server (Ctrl+C)
# Then restart
npm run dev
```

## What This Does

- Maps `mongodb-primary` → `127.0.0.1` (localhost)
- Maps `mongodb-secondary-1` → `127.0.0.1`
- Maps `mongodb-secondary-2` → `127.0.0.1`

When MongoDB tries to connect to these hostnames (discovered from replica set status), they'll resolve to localhost and work correctly.

## Benefits

✅ Replica set features work (automatic failover, read from secondaries)  
✅ Connection string can use `replicaSet=rs0`  
✅ MongoDB driver can discover all members  
✅ No need to remove replica set from connection string

## Troubleshooting

### If hostnames don't resolve:

```bash
# Check /etc/hosts
cat /etc/hosts | grep mongodb

# If missing, add them again
sudo sh -c 'echo "127.0.0.1 mongodb-primary mongodb-secondary-1 mongodb-secondary-2" >> /etc/hosts'
```

### If you need to remove them later:

```bash
# Remove MongoDB entries from /etc/hosts
sudo sed -i '/mongodb-primary\|mongodb-secondary/d' /etc/hosts
```
