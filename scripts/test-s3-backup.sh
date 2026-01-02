#!/bin/bash
# Script to test S3 backup copy functionality

echo "=========================================="
echo "Testing S3 Backup Configuration"
echo "=========================================="
echo ""

CONTAINER_NAME="mongodb-backup"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "❌ Container $CONTAINER_NAME is not running"
    echo "   Start it with: docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml up -d mongodb-backup"
    exit 1
fi

echo "1. Checking environment variables..."
echo "-------------------------------------------"
S3_PATH=$(docker exec $CONTAINER_NAME printenv BACKUP_S3_PATH 2>/dev/null)
S3_HOST_PATH=$(docker exec $CONTAINER_NAME printenv BACKUP_S3_HOST_PATH 2>/dev/null)

if [ -z "$S3_PATH" ]; then
    echo "❌ BACKUP_S3_PATH is not set in container"
    echo "   Set it in .env file: BACKUP_S3_PATH=/mnt/s3-hel"
else
    echo "✅ BACKUP_S3_PATH=$S3_PATH"
fi

if [ -n "$S3_HOST_PATH" ]; then
    echo "ℹ️  BACKUP_S3_HOST_PATH=$S3_HOST_PATH (for volume mapping)"
fi

echo ""
echo "2. Checking S3 directory in container..."
echo "-------------------------------------------"
if docker exec $CONTAINER_NAME test -d /mnt/s3-hel 2>/dev/null; then
    echo "✅ /mnt/s3-hel exists in container"
    
    # Check if writable
    if docker exec $CONTAINER_NAME test -w /mnt/s3-hel 2>/dev/null; then
        echo "✅ /mnt/s3-hel is writable"
    else
        echo "❌ /mnt/s3-hel is NOT writable"
        echo "   Check permissions on host: ls -la $(docker inspect $CONTAINER_NAME --format '{{range .Mounts}}{{if eq .Destination "/mnt/s3-hel"}}{{.Source}}{{end}}{{end}}')"
    fi
    
    # List contents
    echo ""
    echo "Contents of /mnt/s3-hel:"
    docker exec $CONTAINER_NAME ls -lah /mnt/s3-hel 2>/dev/null | head -10 || echo "   (empty or error)"
else
    echo "❌ /mnt/s3-hel does NOT exist in container"
    echo "   Check volume mount in docker-compose.backup.yaml"
fi

echo ""
echo "3. Testing write access..."
echo "-------------------------------------------"
TEST_FILE="/mnt/s3-hel/test-write-$(date +%s)"
if docker exec $CONTAINER_NAME touch "$TEST_FILE" 2>/dev/null; then
    echo "✅ Can write to /mnt/s3-hel"
    docker exec $CONTAINER_NAME rm "$TEST_FILE" 2>/dev/null
else
    echo "❌ Cannot write to /mnt/s3-hel"
    echo "   Error: $(docker exec $CONTAINER_NAME touch "$TEST_FILE" 2>&1)"
fi

echo ""
echo "4. Checking config loading..."
echo "-------------------------------------------"
docker exec $CONTAINER_NAME node -e "
const config = require('./src/config/load');
console.log('S3 Path in config:', config.storage.s3Path || 'NOT SET');
" 2>/dev/null

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
if [ -z "$S3_PATH" ]; then
    echo "❌ BACKUP_S3_PATH is not configured"
    echo ""
    echo "Fix:"
    echo "1. Add to .env file:"
    echo "   BACKUP_S3_PATH=/mnt/s3-hel"
    echo ""
    echo "2. Restart container:"
    echo "   docker-compose -f docker-compose.yaml -f docker-compose.backup.yaml restart mongodb-backup"
else
    echo "✅ Configuration looks good"
    echo ""
    echo "If backups still don't copy to S3, check:"
    echo "1. Container logs: docker logs mongodb-backup | grep -i s3"
    echo "2. Verify backup runs: docker exec mongodb-backup node scripts/manual-backup.js full"
fi
echo ""
