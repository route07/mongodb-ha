const path = require('path');
const fs = require('fs').promises;
const mongodbDump = require('./mongodb-dump');
const compression = require('../utils/compression');
const encryption = require('../encryption/encrypt');
const ipfsUploader = require('../ipfs/upload');
const manifestManager = require('../manifest/manager');
const config = require('../config/load');
const logger = require('../utils/logger');
const notifications = require('../utils/notifications');

class BackupOrchestrator {
  /**
   * Run full backup workflow
   * @returns {Promise<object>} - Backup result
   */
  async runFullBackup() {
    const startTime = Date.now();
    let tempBackupDir = null;
    let compressedFile = null;
    let encryptedFile = null;

    try {
      logger.info('=== Starting Full Backup ===');

      // 1. Create backup directory
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      tempBackupDir = path.join(config.storage.tempDir, `full_backup_${timestamp}`);
      await fs.mkdir(tempBackupDir, { recursive: true });

      // 2. Create MongoDB dump
      logger.info('Step 1/6: Creating MongoDB dump');
      const dumpResult = await mongodbDump.createFullBackup(tempBackupDir);

      // 3. Compress backup
      logger.info('Step 2/6: Compressing backup');
      compressedFile = path.join(config.storage.tempDir, `full_backup_${timestamp}.tar.gz`);
      await compression.compressDirectory(tempBackupDir, compressedFile);

      // 4. Encrypt backup
      logger.info('Step 3/6: Encrypting backup');
      encryptedFile = path.join(config.storage.storageDir, `full_backup_${timestamp}.tar.gz.enc`);
      await encryption.encryptFileStream(compressedFile, encryptedFile);

      const encryptedStats = await fs.stat(encryptedFile);
      logger.info('Backup encrypted', {
        size: encryptedStats.size,
        sizeMB: (encryptedStats.size / 1024 / 1024).toFixed(2),
      });

      // 5. Upload to IPFS
      logger.info('Step 4/6: Uploading to IPFS');
      const uploadResult = await ipfsUploader.uploadFile(encryptedFile);

      // 6. Add to manifest
      logger.info('Step 5/6: Updating manifest');
      await manifestManager.addBackup({
        type: 'full',
        cid: uploadResult.cid,
        timestamp: new Date().toISOString(),
        size: encryptedStats.size,
        duration: dumpResult.duration + ((Date.now() - startTime) / 1000),
        databases: dumpResult.databases,
        localPath: encryptedFile,
      });

      // 7. Upload manifest to IPFS
      logger.info('Step 6/6: Uploading manifest to IPFS');
      await manifestManager.uploadManifest();

      const totalDuration = ((Date.now() - startTime) / 1000).toFixed(2);
      const result = {
        type: 'full',
        cid: uploadResult.cid,
        size: encryptedStats.size,
        duration: parseFloat(totalDuration),
        success: true,
      };

      logger.info('=== Full Backup Completed Successfully ===', result);

      // Send success notification
      await notifications.backupSuccess({
        type: 'full',
        cid: uploadResult.cid,
        size: encryptedStats.size,
        duration: parseFloat(totalDuration),
      });

      // Cleanup temp files
      await this.cleanupTempFiles([tempBackupDir, compressedFile]);

      return result;
    } catch (error) {
      logger.error('=== Full Backup Failed ===', {
        error: error.message,
        stack: error.stack,
      });

      // Send failure notification
      await notifications.backupFailure(error, 'full');

      // Cleanup temp files
      await this.cleanupTempFiles([tempBackupDir, compressedFile, encryptedFile]);

      throw error;
    }
  }

  /**
   * Run incremental backup workflow
   * @returns {Promise<object>} - Backup result
   */
  async runIncrementalBackup() {
    const startTime = Date.now();
    let tempBackupDir = null;
    let compressedFile = null;
    let encryptedFile = null;

    try {
      logger.info('=== Starting Incremental Backup ===');

      // Get last backup time
      const latestFull = await manifestManager.getLatestFullBackup();
      if (!latestFull) {
        throw new Error('No full backup found. Cannot create incremental backup without a base.');
      }

      const lastBackupTime = new Date(latestFull.timestamp);

      // 1. Create backup directory
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
      tempBackupDir = path.join(config.storage.tempDir, `incremental_backup_${timestamp}`);
      await fs.mkdir(tempBackupDir, { recursive: true });

      // 2. Create MongoDB oplog dump
      logger.info('Step 1/6: Creating MongoDB oplog dump');
      const dumpResult = await mongodbDump.createIncrementalBackup(tempBackupDir, lastBackupTime);

      // 3. Compress backup
      logger.info('Step 2/6: Compressing backup');
      compressedFile = path.join(config.storage.tempDir, `incremental_backup_${timestamp}.tar.gz`);
      await compression.compressDirectory(tempBackupDir, compressedFile);

      // 4. Encrypt backup
      logger.info('Step 3/6: Encrypting backup');
      encryptedFile = path.join(config.storage.storageDir, `incremental_backup_${timestamp}.tar.gz.enc`);
      await encryption.encryptFileStream(compressedFile, encryptedFile);

      const encryptedStats = await fs.stat(encryptedFile);
      logger.info('Backup encrypted', {
        size: encryptedStats.size,
        sizeMB: (encryptedStats.size / 1024 / 1024).toFixed(2),
      });

      // 5. Upload to IPFS
      logger.info('Step 4/6: Uploading to IPFS');
      const uploadResult = await ipfsUploader.uploadFile(encryptedFile);

      // 6. Add to manifest
      logger.info('Step 5/6: Updating manifest');
      await manifestManager.addBackup({
        type: 'incremental',
        cid: uploadResult.cid,
        timestamp: new Date().toISOString(),
        size: encryptedStats.size,
        duration: dumpResult.duration + ((Date.now() - startTime) / 1000),
        baseBackup: latestFull.cid,
        oplogStart: lastBackupTime.toISOString(),
        oplogEnd: new Date().toISOString(),
        localPath: encryptedFile,
      });

      // 7. Upload manifest to IPFS
      logger.info('Step 6/6: Uploading manifest to IPFS');
      await manifestManager.uploadManifest();

      const totalDuration = ((Date.now() - startTime) / 1000).toFixed(2);
      const result = {
        type: 'incremental',
        cid: uploadResult.cid,
        size: encryptedStats.size,
        duration: parseFloat(totalDuration),
        success: true,
      };

      logger.info('=== Incremental Backup Completed Successfully ===', result);

      // Send success notification
      await notifications.backupSuccess({
        type: 'incremental',
        cid: uploadResult.cid,
        size: encryptedStats.size,
        duration: parseFloat(totalDuration),
      });

      // Cleanup temp files
      await this.cleanupTempFiles([tempBackupDir, compressedFile]);

      return result;
    } catch (error) {
      logger.error('=== Incremental Backup Failed ===', {
        error: error.message,
        stack: error.stack,
      });

      // Send failure notification
      await notifications.backupFailure(error, 'incremental');

      // Cleanup temp files
      await this.cleanupTempFiles([tempBackupDir, compressedFile, encryptedFile]);

      throw error;
    }
  }

  /**
   * Clean up temporary files
   * @param {Array<string>} paths - Paths to clean up
   */
  async cleanupTempFiles(paths) {
    for (const filePath of paths) {
      if (!filePath) continue;

      try {
        const stats = await fs.stat(filePath);
        if (stats.isDirectory()) {
          await fs.rm(filePath, { recursive: true, force: true });
        } else {
          await fs.unlink(filePath);
        }
        logger.debug('Cleaned up temp file', { path: filePath });
      } catch (error) {
        // Ignore errors (file might not exist)
        if (error.code !== 'ENOENT') {
          logger.warn('Failed to cleanup temp file', { path: filePath, error: error.message });
        }
      }
    }
  }
}

module.exports = new BackupOrchestrator();
