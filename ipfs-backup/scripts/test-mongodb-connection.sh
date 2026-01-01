#!/bin/bash
# Test MongoDB connection from backup container

echo "Testing MongoDB connection..."

# Test connection to secondary-1
echo "Testing mongodb-secondary-1:27017..."
mongosh "mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@mongodb-secondary-1:27017/?replicaSet=rs0&tls=true&tlsCAFile=/etc/mongo/ssl/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin&readPreference=secondary" --eval "db.adminCommand('ping')"

echo ""
echo "Testing with mongodump..."
mongodump --uri="mongodb://rbdbuser:adsijeoirFgfsd092rvcsxvsdewRS@mongodb-secondary-1:27017/?replicaSet=rs0&tls=true&tlsCAFile=/etc/mongo/ssl/ca.crt&tlsAllowInvalidCertificates=true&authSource=admin&readPreference=secondary" --out=/tmp/test-dump --gzip
