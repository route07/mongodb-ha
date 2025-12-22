# Fix: Primary Not Primary After Restart

## The Problem

After restarting containers, the primary node is no longer primary (`rs.isMaster().ismaster` returns `false`). This happens because:

1. Containers restart
2. Replica set needs time to re-elect a primary
3. Or nodes can't communicate with each other
4. Or replica set needs to be re-initialized

## Quick Fix Steps

### Step 1: Check Replica Set Status

```bash
cd ~/ha-mongodb
source .env

docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status()"
```

Look for:
- Which node is PRIMARY (if any)
- Which nodes are SECONDARY
- Which nodes are DOWN or UNREACHABLE
- Any error messages

### Step 2: Check All Containers Are Running

```bash
docker-compose ps
```

All three MongoDB containers should be `Up` and `healthy`.

### Step 3: Wait a Bit (Sometimes It Just Needs Time)

MongoDB replica sets can take 30-60 seconds to re-elect a primary after restart. Wait a bit and check again:

```bash
sleep 30
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.isMaster().ismaster"
```

### Step 4: If Still Not Primary - Force Re-election

If no primary is elected after waiting, you can force a re-election:

```bash
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
    try {
      var status = rs.status();
      print('Current members:');
      status.members.forEach(function(m) {
        print('  ' + m.name + ': ' + m.stateStr);
      });
      print('');
      print('Attempting to step down current primary (if any)...');
      try {
        rs.stepDown(60);
        print('Stepped down. Waiting for re-election...');
      } catch(e) {
        print('No primary to step down, or already stepped down');
      }
    } catch(e) {
      print('Error: ' + e.message);
    }
  "
```

Wait 30 seconds, then check again.

### Step 5: If Nodes Are Down - Check Connectivity

If some nodes show as DOWN, check if they can communicate:

```bash
# From primary container, ping secondaries
docker exec mongo-primary ping -c 2 mongodb-secondary-1
docker exec mongo-primary ping -c 2 mongodb-secondary-2

# Check if they're on the same network
docker network inspect ha-mongodb_db-network | grep -A 5 "mongodb"
```

### Step 6: If Replica Set Is Not Initialized

If `rs.status()` shows the replica set is not initialized, re-initialize it:

```bash
cd ~/ha-mongodb
./scripts/init-replica-set.sh
```

Or manually:

```bash
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
    try {
      var status = rs.status();
      print('Replica set already initialized');
    } catch(e) {
      print('Initializing replica set...');
      rs.initiate({
        _id: 'rs0',
        members: [
          { _id: 0, host: 'mongodb-primary:27017', priority: 2 },
          { _id: 1, host: 'mongodb-secondary-1:27017', priority: 1 },
          { _id: 2, host: 'mongodb-secondary-2:27017', priority: 1 }
        ]
      });
      print('Replica set initialized. Waiting for primary election...');
    }
  "
```

Wait 30 seconds, then check again.

## Common Issues

### Issue 1: All Nodes Are Secondary

**Symptom**: `rs.status()` shows all nodes as SECONDARY, no PRIMARY

**Fix**: Wait longer (up to 60 seconds) or force re-election (Step 4)

### Issue 2: Nodes Can't Communicate

**Symptom**: Some nodes show as DOWN or UNREACHABLE

**Fix**: 
- Check containers are running: `docker-compose ps`
- Check network: `docker network inspect ha-mongodb_db-network`
- Restart containers: `docker-compose restart`

### Issue 3: Replica Set Not Initialized

**Symptom**: `rs.status()` throws error "no replset config has been received"

**Fix**: Run Step 6 to re-initialize

### Issue 4: KeyFile Issues

**Symptom**: Nodes can't authenticate with each other

**Fix**: Check keyFile exists and has correct permissions:
```bash
ls -la tls-certs/keyfile
# Should show 600 permissions
```

## Quick Diagnostic Script

Run this to see the full status:

```bash
cd ~/ha-mongodb
source .env

docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
    print('=== Replica Set Status ===');
    try {
      var status = rs.status();
      print('Set Name: ' + status.set);
      print('Members:');
      status.members.forEach(function(m) {
        print('  ' + m.name + ': ' + m.stateStr + 
              (m.health === 1 ? ' (healthy)' : ' (unhealthy)'));
      });
      print('');
      print('Primary: ' + (status.members.find(m => m.stateStr === 'PRIMARY')?.name || 'NONE'));
    } catch(e) {
      print('Error: ' + e.message);
      print('Replica set may not be initialized');
    }
  "
```

## Summary

1. **Check status** - See what's happening
2. **Wait** - Sometimes it just needs time (30-60 seconds)
3. **Force re-election** - If waiting doesn't work
4. **Re-initialize** - If replica set is not initialized
5. **Check connectivity** - If nodes can't communicate

Most of the time, just waiting 30-60 seconds after restart is enough for MongoDB to re-elect a primary.
