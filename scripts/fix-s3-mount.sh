#!/bin/bash
# Script to fix S3 mount issue in Docker Compose

echo "=========================================="
echo "Fixing S3 Mount for Docker Compose"
echo "=========================================="
echo ""

S3_PATH="${BACKUP_S3_HOST_PATH:-/home/tschain/s3-hel}"

echo "Checking S3 mount path: $S3_PATH"
echo ""

# Check if path exists
if [ ! -d "$S3_PATH" ]; then
    echo "❌ Directory does not exist: $S3_PATH"
    echo "   Please ensure your S3 storage is mounted at this location"
    exit 1
fi

# Check if it's a mount point
if mountpoint -q "$S3_PATH" 2>/dev/null; then
    echo "✅ $S3_PATH is a mount point"
elif [ -d "$S3_PATH" ]; then
    echo "⚠️  $S3_PATH exists but may not be a mount point"
    echo "   This is okay if it's a regular directory"
else
    echo "❌ $S3_PATH does not exist"
    exit 1
fi

# Check permissions
if [ -w "$S3_PATH" ]; then
    echo "✅ $S3_PATH is writable"
else
    echo "⚠️  $S3_PATH is not writable"
    echo "   You may need to fix permissions:"
    echo "   sudo chmod 755 $S3_PATH"
fi

echo ""
echo "=========================================="
echo "Solution"
echo "=========================================="
echo ""
echo "The Docker Compose file has been updated to use:"
echo "  type: bind"
echo "  create_host_path: false"
echo ""
echo "This tells Docker NOT to create the directory (it must exist)."
echo ""
echo "If you still get errors, try:"
echo ""
echo "1. Ensure the directory exists and is accessible:"
echo "   ls -la $S3_PATH"
echo ""
echo "2. Check Docker can access it:"
echo "   docker run --rm -v $S3_PATH:/test alpine ls -la /test"
echo ""
echo "3. If using SELinux, you may need:"
echo "   sudo chcon -Rt svirt_sandbox_file_t $S3_PATH"
echo ""
