# Init Containers Behavior

## Overview

The MongoDB setup includes two init containers that run once to set up the database:

1. **`mongodb-init-user`** - Ensures the root user exists
2. **`mongodb-init`** - Initializes the replica set

## How They Work

### Current Behavior

Both containers have `restart: "no"`, which means:

- ✅ **First run**: They execute and complete their tasks
- ✅ **Subsequent runs**: If they completed successfully (exited with code 0), they show as "exited (0)" and **won't run again** on `docker-compose up`
- ✅ **Idempotent**: Both scripts check if their work is already done before doing anything:
  - `init-user.sh` checks if the user exists
  - `init-replica-set.sh` checks if the replica set is already initialized

### What Happens on `docker-compose up`

```bash
docker-compose up -d
```

**Scenario 1: Init containers already completed successfully**
- Containers show as: `mongo-init-user (exited 0)`, `mongo-init (exited 0)`
- They **won't run again** - Docker Compose sees they're already done
- MongoDB services start normally

**Scenario 2: Init containers don't exist or were removed**
- They will run once to complete initialization
- After completion, they exit and won't run again

**Scenario 3: You want to re-run init containers**
```bash
# Remove the containers
docker-compose rm -f mongodb-init-user mongodb-init

# Start again (they'll run)
docker-compose up -d
```

## When Init Containers Run

### `mongodb-init-user`
- Runs after `mongodb-primary` starts
- Checks if user exists → exits immediately if yes
- Creates user if missing
- Takes ~5-10 seconds if user already exists
- Takes ~15-30 seconds if creating user

### `mongodb-init`
- Runs after all MongoDB nodes are healthy AND `mongodb-init-user` completes
- Checks if replica set is initialized → exits immediately if yes
- Initializes replica set if not done
- Takes ~5 seconds if already initialized
- Takes ~30-60 seconds if initializing

## Performance Impact

Since both scripts are idempotent and exit quickly if work is already done:

- **First startup**: ~60-90 seconds (user creation + replica set init)
- **Subsequent startups**: ~5-10 seconds (just checks, no work)

## Disabling Init Containers

If you want to disable init containers (not recommended):

### Option 1: Use Docker Compose Profiles

The init containers can be excluded using profiles:

```bash
# Start without init containers
docker-compose --profile init up -d
```

But this requires adding profiles to docker-compose.yaml (currently not enabled).

### Option 2: Comment Out Services

Temporarily comment out the init container services in `docker-compose.yaml`:

```yaml
# mongodb-init-user:
#   ...

# mongodb-init:
#   ...
```

### Option 3: Manual Initialization

Run the scripts manually when needed:

```bash
# Create user manually
docker run --rm --network ha-mongodb_db-network \
  -v $(pwd)/tls-certs:/etc/mongo/ssl:ro \
  -v $(pwd)/scripts:/scripts:ro \
  -e MONGO_INITDB_ROOT_USERNAME=your_user \
  -e MONGO_INITDB_ROOT_PASSWORD=your_pass \
  mongo:7.0 \
  bash /scripts/init-user.sh mongodb-primary 27017

# Initialize replica set manually
docker run --rm --network ha-mongodb_db-network \
  -v $(pwd)/tls-certs:/etc/mongo/ssl:ro \
  -v $(pwd)/scripts:/scripts:ro \
  -e MONGO_INITDB_ROOT_USERNAME=your_user \
  -e MONGO_INITDB_ROOT_PASSWORD=your_pass \
  -e REPLICA_SET_NAME=rs0 \
  mongo:7.0 \
  bash /scripts/init-replica-set.sh
```

## Troubleshooting

### Init containers keep running

If init containers show as "running" for a long time:

```bash
# Check logs
docker-compose logs mongodb-init-user
docker-compose logs mongodb-init

# Check if they're stuck
docker ps | grep mongo-init
```

### Init containers fail

If init containers exit with non-zero code:

```bash
# Check exit code
docker inspect mongo-init-user --format='{{.State.ExitCode}}'
docker inspect mongo-init --format='{{.State.ExitCode}}'

# Check logs
docker-compose logs mongodb-init-user
docker-compose logs mongodb-init
```

### Force re-run init containers

```bash
# Remove containers
docker-compose rm -f mongodb-init-user mongodb-init

# Start again
docker-compose up -d
```

## Best Practices

1. **Let them run**: The init containers are designed to be safe and fast on subsequent runs
2. **Check logs**: If something seems wrong, check the init container logs
3. **Don't remove manually**: Unless you need to re-initialize, let Docker Compose manage them
4. **Monitor first startup**: The first startup takes longer - this is normal

## Summary

- ✅ Init containers run **once** on first startup
- ✅ They exit quickly on subsequent startups (idempotent checks)
- ✅ They don't impact normal operations after initialization
- ✅ Safe to leave in docker-compose.yaml

The current setup is optimal - init containers ensure your MongoDB is properly configured without unnecessary overhead.
