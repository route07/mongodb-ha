#!/bin/bash
# Script to check and fix MongoDB bind address issue

echo "=========================================="
echo "Fixing MongoDB Bind Address"
echo "=========================================="
echo ""

if [ -z "$1" ]; then
    echo "Usage: $0 <server-ip>"
    echo "Example: $0 192.168.2.6"
    echo ""
    echo "Or run on the server itself:"
    echo "  $0 local"
    exit 1
fi

SERVER_IP="$1"

if [ "$SERVER_IP" = "local" ]; then
    echo "Checking local MongoDB bind address..."
    echo ""
    
    echo "1. Checking if MongoDB is listening..."
    echo "-------------------------------------------"
    docker exec mongo-secondary-2 netstat -tlnp 2>/dev/null | grep 27017 || \
    docker exec mongo-secondary-2 ss -tlnp 2>/dev/null | grep 27017
    
    echo ""
    echo "2. Checking docker-compose.yaml..."
    echo "-------------------------------------------"
    if grep -q "bind_ip_all" docker-compose.yaml; then
        echo "✅ --bind_ip_all is present in docker-compose.yaml"
    else
        echo "❌ --bind_ip_all is MISSING in docker-compose.yaml"
        echo ""
        echo "Fix: Add --bind_ip_all to the command section"
    fi
    
    echo ""
    echo "3. Checking container command..."
    echo "-------------------------------------------"
    docker inspect mongo-secondary-2 --format='{{.Config.Cmd}}' | grep -q "bind_ip_all" && \
        echo "✅ --bind_ip_all is in container command" || \
        echo "❌ --bind_ip_all is NOT in container command"
    
    echo ""
    echo "4. If --bind_ip_all is missing, restart container:"
    echo "   docker-compose restart mongodb-secondary-2"
    
else
    echo "Checking remote server: $SERVER_IP"
    echo ""
    
    echo "1. Testing network connectivity..."
    if ping -c 2 "$SERVER_IP" > /dev/null 2>&1; then
        echo "✅ Server is reachable"
    else
        echo "❌ Server is NOT reachable"
        exit 1
    fi
    
    echo ""
    echo "2. Testing port 27017..."
    if timeout 3 bash -c "cat < /dev/null > /dev/tcp/$SERVER_IP/27017" 2>/dev/null; then
        echo "✅ Port 27017 is accessible"
    else
        echo "❌ Port 27017 is NOT accessible (Connection refused)"
        echo ""
        echo "This usually means:"
        echo "  - MongoDB is only listening on localhost (127.0.0.1)"
        echo "  - Need to add --bind_ip_all to docker-compose.yaml"
        echo "  - Or firewall is blocking (but less likely if ping works)"
        echo ""
        echo "Fix on remote server ($SERVER_IP):"
        echo "  1. SSH to the server"
        echo "  2. Check docker-compose.yaml has --bind_ip_all"
        echo "  3. Restart container: docker-compose restart mongodb-secondary-2"
    fi
fi

echo ""
echo "=========================================="
