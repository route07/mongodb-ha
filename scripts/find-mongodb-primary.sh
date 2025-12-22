#!/bin/bash
# Script to find where mongodb-primary is used in your application

echo "=========================================="
echo "Searching for 'mongodb-primary' usage"
echo "=========================================="
echo ""

# Check if we're in the right directory
if [ ! -f "package.json" ] && [ ! -f ".env" ] && [ ! -f ".env.local" ]; then
    echo "⚠️  Warning: Doesn't look like an application directory"
    echo "   Run this script from your application root directory"
    echo ""
fi

echo "1. Environment files (.env, .env.local, etc.):"
echo "-------------------------------------------"
found_env=false
for file in .env .env.local .env.development .env.production .env.staging .env.development.local .env.production.local; do
    if [ -f "$file" ]; then
        if grep -q "mongodb-primary" "$file" 2>/dev/null; then
            echo "   ✓ Found in: $file"
            grep -n "mongodb-primary" "$file" | sed 's/^/      /'
            found_env=true
        fi
    fi
done
if [ "$found_env" = false ]; then
    echo "   ✗ No matches in environment files"
    echo "   (This is good! But check if MONGODB_URI is set elsewhere)"
fi
echo ""

echo "1b. All MONGODB_URI values (to see what's actually set):"
echo "-------------------------------------------"
for file in .env .env.local .env.development .env.production .env.staging .env.development.local .env.production.local; do
    if [ -f "$file" ]; then
        if grep -q "MONGODB_URI" "$file" 2>/dev/null; then
            echo "   In $file:"
            grep "MONGODB_URI" "$file" | sed 's/:[^:@]*@/:****@/g' | sed 's/^/      /'
        fi
    fi
done
echo ""

echo "2. JavaScript/TypeScript source files:"
echo "-------------------------------------------"
js_matches=$(grep -r "mongodb-primary" \
    --include="*.js" \
    --include="*.ts" \
    --include="*.jsx" \
    --include="*.tsx" \
    --exclude-dir=node_modules \
    --exclude-dir=.next \
    --exclude-dir=.git \
    . 2>/dev/null | head -10)

if [ -z "$js_matches" ]; then
    echo "   ✗ No matches in source files"
else
    echo "$js_matches" | while IFS= read -r line; do
        echo "   ✓ $line"
    done
fi
echo ""

echo "3. Configuration files:"
echo "-------------------------------------------"
config_files=$(find . -maxdepth 3 \
    \( -name "*.config.*" -o -name "config.*" -o -name "next.config.*" \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.next/*" \
    2>/dev/null)

found_config=false
for file in $config_files; do
    if grep -q "mongodb-primary" "$file" 2>/dev/null; then
        echo "   ✓ Found in: $file"
        grep -n "mongodb-primary" "$file" | sed 's/^/      /'
        found_config=true
    fi
done
if [ "$found_config" = false ]; then
    echo "   ✗ No matches in config files"
fi
echo ""

echo "4. Docker Compose files:"
echo "-------------------------------------------"
docker_files=$(find . -maxdepth 2 \
    \( -name "docker-compose*.yaml" -o -name "docker-compose*.yml" \) \
    2>/dev/null)

found_docker=false
for file in $docker_files; do
    if grep -q "mongodb-primary" "$file" 2>/dev/null; then
        echo "   ✓ Found in: $file"
        grep -n "mongodb-primary" "$file" | sed 's/^/      /'
        found_docker=true
    fi
done
if [ "$found_docker" = false ]; then
    echo "   ✗ No matches in docker-compose files"
fi
echo ""

echo "5. Package.json scripts:"
echo "-------------------------------------------"
if [ -f "package.json" ]; then
    if grep -q "mongodb-primary" package.json 2>/dev/null; then
        echo "   ✓ Found in package.json"
        grep -n "mongodb-primary" package.json | sed 's/^/      /'
    else
        echo "   ✗ No matches in package.json"
    fi
else
    echo "   ✗ package.json not found"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "If you found matches above, replace 'mongodb-primary' with:"
echo "  - 'localhost' (if app is on same server as MongoDB)"
echo "  - 'YOUR_SERVER_IP' (if app is on different server)"
echo ""
echo "Or use separate environment variables:"
echo "  MONGODB_HOST=localhost"
echo "  MONGODB_PORT=27017"
echo "  # ... etc"
echo ""
echo "See: docs/BUILD_CONNECTION_STRING.md for details"
echo ""
