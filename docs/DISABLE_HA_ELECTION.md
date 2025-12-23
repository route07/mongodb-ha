# Disable HA Election

This guide explains how to temporarily disable automatic primary election in MongoDB replica sets.

## When to Use

Disable HA election when:
- You're experiencing election issues and need stability
- You want to prevent automatic failover during maintenance
- You need to troubleshoot election-related problems
- You want to ensure a specific node remains primary

## ⚠️ Important Warnings

**Disabling HA election means:**
- If the primary fails, **no automatic failover will occur**
- Your database will be **unavailable** until you manually fix it
- You must **manually promote a secondary** if the primary fails
- This should only be used **temporarily** while fixing issues

## Quick Start

### Disable HA Election

```bash
cd ~/ha-mongodb
./scripts/disable-ha-election.sh
```

This script will:
1. Set primary priority to **100** (very high)
2. Set secondary priorities to **0** (prevents election)
3. Freeze secondaries for 24 hours (prevents elections)

### Re-enable HA Election

```bash
./scripts/enable-ha-election.sh
```

This script will:
1. Unfreeze secondaries
2. Restore primary priority to **2** (normal)
3. Restore secondary priorities to **1** (normal)

## What the Scripts Do

### disable-ha-election.sh

1. **Finds the current primary** node
2. **Updates replica set configuration**:
   - Primary: `priority: 100`
   - Secondaries: `priority: 0`
3. **Freezes secondaries**: `rs.freeze(86400)` (24 hours)
4. **Verifies** the configuration

### enable-ha-election.sh

1. **Unfreezes secondaries**: `rs.freeze(0)`
2. **Restores normal priorities**:
   - Primary: `priority: 2`
   - Secondaries: `priority: 1`
3. **Verifies** the configuration

## Manual Commands

If you prefer to do it manually:

### Disable Elections

```bash
# Connect to primary
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin

# Update configuration
cfg = rs.conf();
cfg.members[0].priority = 100;  # Primary
cfg.members[1].priority = 0;      # Secondary 1
cfg.members[2].priority = 0;      # Secondary 2
rs.reconfig(cfg);

# Freeze secondaries (from secondary containers)
rs.freeze(86400);  # 24 hours
```

### Re-enable Elections

```bash
# Unfreeze secondaries
docker exec mongodb-secondary-1 mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.freeze(0)"

docker exec mongodb-secondary-2 mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.freeze(0)"

# Restore priorities (from primary)
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "
    cfg = rs.conf();
    cfg.members[0].priority = 2;
    cfg.members[1].priority = 1;
    cfg.members[2].priority = 1;
    rs.reconfig(cfg);
  "
```

## Verify Configuration

Check current priorities:

```bash
./scripts/check-replica-set-status.sh
```

Or manually:

```bash
docker exec mongo-primary mongosh --tls \
  --tlsAllowInvalidCertificates \
  --tlsCAFile /etc/mongo/ssl/ca.crt \
  -u "$MONGO_INITDB_ROOT_USERNAME" \
  -p "$MONGO_INITDB_ROOT_PASSWORD" \
  --authenticationDatabase admin \
  --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr + ' (priority: ' + (m.priority || 1) + ')'))"
```

## Troubleshooting

### Script fails: "Could not find primary"

**Solution**: Make sure at least one MongoDB container is running and is primary:
```bash
./scripts/check-replica-set-status.sh
```

### Script fails: "Failed to update replica set configuration"

**Possible causes**:
- Not connected to primary
- Replica set not initialized
- Network issues

**Solution**:
1. Check replica set status
2. Ensure you're running from the correct directory with `.env` file
3. Check container logs: `docker logs mongo-primary`

### Elections still happening after disabling

**Check**:
1. Verify priorities: `rs.conf().members.forEach(m => print(m.host + ': ' + m.priority))`
2. Check if secondaries are frozen: `rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))`
3. Ensure freeze hasn't expired (freeze lasts 24 hours)

## Best Practices

1. **Only disable temporarily** - Re-enable as soon as issues are fixed
2. **Monitor primary health** - Since failover is disabled, watch for primary issues
3. **Have a recovery plan** - Know how to manually promote a secondary if needed
4. **Document why** - Note why elections were disabled and when to re-enable

## Related Documentation

- [Understanding Primary Failover](./UNDERSTANDING_PRIMARY_FAILOVER.md)
- [Fix Primary After Restart](./FIX_PRIMARY_AFTER_RESTART.md)
- [Troubleshooting](./TROUBLESHOOTING.md)
