#!/bin/bash
# Script to add MongoDB Docker hostnames to /etc/hosts

echo "=========================================="
echo "Adding MongoDB hostnames to /etc/hosts"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  This script needs sudo privileges"
    echo "   Run: sudo $0"
    exit 1
fi

# Backup /etc/hosts
if [ ! -f /etc/hosts.backup ]; then
    cp /etc/hosts /etc/hosts.backup
    echo "✓ Backed up /etc/hosts to /etc/hosts.backup"
else
    echo "✓ Backup already exists: /etc/hosts.backup"
fi
echo ""

# Check if entries already exist
if grep -q "mongodb-primary" /etc/hosts 2>/dev/null; then
    echo "⚠️  MongoDB hostnames already exist in /etc/hosts:"
    grep "mongodb-primary\|mongodb-secondary" /etc/hosts
    echo ""
    read -p "Do you want to update them? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
    # Remove old entries
    sed -i '/mongodb-primary\|mongodb-secondary/d' /etc/hosts
    echo "✓ Removed old entries"
fi

# Add new entries
echo "127.0.0.1 mongodb-primary" >> /etc/hosts
echo "127.0.0.1 mongodb-secondary-1" >> /etc/hosts
echo "127.0.0.1 mongodb-secondary-2" >> /etc/hosts

echo ""
echo "✓ Added MongoDB hostnames to /etc/hosts:"
echo "   127.0.0.1 mongodb-primary"
echo "   127.0.0.1 mongodb-secondary-1"
echo "   127.0.0.1 mongodb-secondary-2"
echo ""

# Verify
echo "Verifying hostname resolution:"
ping -c 1 mongodb-primary > /dev/null 2>&1 && echo "   ✓ mongodb-primary resolves" || echo "   ✗ mongodb-primary failed"
ping -c 1 mongodb-secondary-1 > /dev/null 2>&1 && echo "   ✓ mongodb-secondary-1 resolves" || echo "   ✗ mongodb-secondary-1 failed"
ping -c 1 mongodb-secondary-2 > /dev/null 2>&1 && echo "   ✓ mongodb-secondary-2 resolves" || echo "   ✗ mongodb-secondary-2 failed"
echo ""

echo "=========================================="
echo "Done! You can now use replicaSet=rs0"
echo "=========================================="
echo ""
echo "Update your .env.local to include replicaSet:"
echo "  MONGODB_URI=mongodb://rbdbuser:password@localhost:27017/w3kyc?replicaSet=rs0&tls=true&tlsCAFile=./tls-certs/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin"
echo ""
echo "Then restart your application."
