FROM node:18-alpine

# Install MongoDB tools
RUN apk add --no-cache mongodb-tools bash

WORKDIR /app

# Copy package files
COPY package*.json ./
RUN npm ci --production

# Copy application code
COPY . .

# Create directories
RUN mkdir -p /tmp/mongodb-backups /data/backups /var/log/backups

# Set permissions
RUN chmod +x scripts/*.sh 2>/dev/null || true

# Run backup service
CMD ["node", "src/index.js"]
