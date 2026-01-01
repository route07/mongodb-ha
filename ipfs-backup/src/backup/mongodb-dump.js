const { exec } = require('child_process');
const { promisify } = require('util');
const fs = require('fs').promises;
const path = require('path');
const config = require('../config/load');
const logger = require('../utils/logger');

const execAsync = promisify(exec);

class MongoDBDump {
  /**
   * Parse MongoDB URI to extract connection parameters
   * @param {string} uri - MongoDB connection URI
   * @returns {object} - Parsed connection parameters
   */
  parseUri(uri) {
    // Extract components from URI
    const url = new URL(uri.replace('mongodb://', 'http://'));
    
    return {
      host: url.hostname,
      port: url.port || '27017',
      username: url.username,
      password: url.password,
      database: url.pathname.slice(1) || '',
      params: url.search,
    };
  }

  /**
   * Build mongodump command arguments
   * @param {object} options - Backup options
   * @returns {Array} - Command arguments
   */
  buildDumpArgs(options = {}) {
    const { uri, outputDir, full = true, oplog = false } = options;
    const parsed = this.parseUri(uri);
    
    const args = [
      '--uri', uri,
      '--out', outputDir,
    ];

    if (full) {
      // Full backup - all databases
      // No --db flag means all databases
    } else if (parsed.database) {
      // Single database backup
      args.push('--db', parsed.database);
    }

    if (oplog) {
      args.push('--oplog');
    }

    // TLS options are in URI, but we can add explicit flags if needed
    args.push('--gzip'); // Compress during dump

    return args;
  }

  /**
   * Create full backup of all databases
   * @param {string} outputDir - Directory to save backup
   * @returns {Promise<object>} - Backup metadata
   */
  async createFullBackup(outputDir) {
    try {
      logger.info('Starting full backup', { outputDir });
      const startTime = Date.now();

      // Ensure output directory exists
      await fs.mkdir(outputDir, { recursive: true });

      const args = this.buildDumpArgs({
        uri: config.mongodb.uri,
        outputDir,
        full: true,
        oplog: false,
      });

      const command = `${config.mongodbTools.mongodump} ${args.join(' ')}`;
      logger.debug('Executing mongodump', { command: command.replace(/:[^:@]+@/, ':****@') });

      const { stdout, stderr } = await execAsync(command, {
        maxBuffer: 10 * 1024 * 1024, // 10MB buffer
      });

      if (stderr && !stderr.includes('writing') && !stderr.includes('done')) {
        logger.warn('mongodump stderr', { stderr });
      }

      const duration = ((Date.now() - startTime) / 1000).toFixed(2);
      logger.info('Full backup completed', { outputDir, duration: `${duration}s` });

      // Get backup metadata
      const metadata = await this.getBackupMetadata(outputDir);

      return {
        type: 'full',
        outputDir,
        duration: parseFloat(duration),
        ...metadata,
      };
    } catch (error) {
      logger.error('Full backup failed', { error: error.message, outputDir });
      throw error;
    }
  }

  /**
   * Create incremental backup using oplog
   * @param {string} outputDir - Directory to save backup
   * @param {Date} lastBackupTime - Timestamp of last backup
   * @returns {Promise<object>} - Backup metadata
   */
  async createIncrementalBackup(outputDir, lastBackupTime) {
    try {
      logger.info('Starting incremental backup', { outputDir, lastBackupTime });
      const startTime = Date.now();

      // Ensure output directory exists
      await fs.mkdir(outputDir, { recursive: true });

      const args = this.buildDumpArgs({
        uri: config.mongodb.uri,
        outputDir,
        full: false, // Oplog only
        oplog: true,
      });

      const command = `${config.mongodbTools.mongodump} ${args.join(' ')}`;
      logger.debug('Executing mongodump with oplog', { command: command.replace(/:[^:@]+@/, ':****@') });

      const { stdout, stderr } = await execAsync(command, {
        maxBuffer: 10 * 1024 * 1024,
      });

      if (stderr && !stderr.includes('writing') && !stderr.includes('done')) {
        logger.warn('mongodump stderr', { stderr });
      }

      const duration = ((Date.now() - startTime) / 1000).toFixed(2);
      logger.info('Incremental backup completed', { outputDir, duration: `${duration}s` });

      // Get backup metadata
      const metadata = await this.getBackupMetadata(outputDir);

      return {
        type: 'incremental',
        outputDir,
        duration: parseFloat(duration),
        lastBackupTime,
        ...metadata,
      };
    } catch (error) {
      logger.error('Incremental backup failed', { error: error.message, outputDir });
      throw error;
    }
  }

  /**
   * Get backup metadata (size, databases, etc.)
   * @param {string} backupDir - Backup directory
   * @returns {Promise<object>} - Backup metadata
   */
  async getBackupMetadata(backupDir) {
    try {
      const entries = await fs.readdir(backupDir);
      const databases = entries.filter(entry => {
        // Check if it's a directory (database)
        return fs.stat(path.join(backupDir, entry)).then(stat => stat.isDirectory()).catch(() => false);
      });

      // Calculate total size
      let totalSize = 0;
      const calculateSize = async (dir) => {
        const entries = await fs.readdir(dir);
        for (const entry of entries) {
          const fullPath = path.join(dir, entry);
          const stat = await fs.stat(fullPath);
          if (stat.isDirectory()) {
            await calculateSize(fullPath);
          } else {
            totalSize += stat.size;
          }
        }
      };
      await calculateSize(backupDir);

      return {
        databases: databases.length > 0 ? databases : ['all'],
        size: totalSize,
        timestamp: new Date().toISOString(),
      };
    } catch (error) {
      logger.warn('Failed to get backup metadata', { error: error.message });
      return {
        databases: [],
        size: 0,
        timestamp: new Date().toISOString(),
      };
    }
  }
}

module.exports = new MongoDBDump();
