require('dotenv').config();
const fs = require('fs');
const path = require('path');

class Config {
  constructor() {
    this.load();
    this.validate();
  }

  load() {
    // MongoDB
    this.mongodb = {
      uri: process.env.MONGODB_URI || '',
    };

    // Encryption
    this.encryption = {
      key: process.env.BACKUP_ENCRYPTION_KEY || '',
      iterations: parseInt(process.env.ENCRYPTION_KEY_DERIVATION_ITERATIONS || '100000', 10),
    };

    // IPFS
    this.ipfs = {
      node1Url: process.env.IPFS_NODE_1_URL || '',
      node2Url: process.env.IPFS_NODE_2_URL || '',
      replicationFactor: parseInt(process.env.IPFS_REPLICATION_FACTOR || '2', 10),
    };

    // Backup Schedule
    this.schedule = {
      full: process.env.FULL_BACKUP_SCHEDULE || '0 2 * * 0',
      incremental: process.env.INCREMENTAL_BACKUP_SCHEDULE || '0 2 * * *',
      retentionDays: parseInt(process.env.BACKUP_RETENTION_DAYS || '90', 10),
    };

    // Local Storage
    this.storage = {
      tempDir: process.env.BACKUP_TEMP_DIR || '/tmp/mongodb-backups',
      storageDir: process.env.BACKUP_STORAGE_DIR || '/data/backups',
      localRetentionDays: parseInt(process.env.BACKUP_LOCAL_RETENTION_DAYS || '7', 10),
    };

    // Notifications
    this.notifications = {
      webhookUrl: process.env.WEBHOOK_URL || '',
      enabled: process.env.WEBHOOK_ENABLED === 'true',
    };

    // Logging
    this.logging = {
      level: process.env.LOG_LEVEL || 'info',
      dir: process.env.LOG_DIR || '/var/log/backups',
    };

    // MongoDB Tools
    this.mongodbTools = {
      mongodump: process.env.MONGODUMP_PATH || 'mongodump',
      mongorestore: process.env.MONGORESTORE_PATH || 'mongorestore',
    };
  }

  validate() {
    const required = [
      { key: 'MONGODB_URI', value: this.mongodb.uri },
      { key: 'BACKUP_ENCRYPTION_KEY', value: this.encryption.key },
      { key: 'IPFS_NODE_1_URL', value: this.ipfs.node1Url },
      { key: 'IPFS_NODE_2_URL', value: this.ipfs.node2Url },
    ];

    const missing = required.filter(({ value }) => !value);
    if (missing.length > 0) {
      throw new Error(`Missing required environment variables: ${missing.map(m => m.key).join(', ')}`);
    }

    // Validate encryption key format (should be base64)
    if (this.encryption.key && Buffer.from(this.encryption.key, 'base64').length !== 32) {
      throw new Error('BACKUP_ENCRYPTION_KEY must be a base64-encoded 32-byte (256-bit) key');
    }

    // Create directories if they don't exist
    [this.storage.tempDir, this.storage.storageDir, this.logging.dir].forEach(dir => {
      if (dir && !fs.existsSync(dir)) {
        fs.mkdirSync(dir, { recursive: true });
      }
    });
  }

  // Mask sensitive values for logging
  getSafeConfig() {
    return {
      ...this,
      mongodb: {
        ...this.mongodb,
        uri: this.mongodb.uri.replace(/:[^:@]+@/, ':****@'),
      },
      encryption: {
        ...this.encryption,
        key: this.encryption.key ? '****' : '',
      },
    };
  }
}

module.exports = new Config();
