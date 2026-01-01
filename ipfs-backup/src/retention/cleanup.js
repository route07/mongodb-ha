const ipfsUploader = require('../ipfs/upload');
const manifestManager = require('../manifest/manager');
const config = require('../config/load');
const logger = require('../utils/logger');
const fs = require('fs').promises;
const path = require('path');

class RetentionCleanup {
  /**
   * Clean up old backups based on retention policy
   * @returns {Promise<object>} - Cleanup results
   */
  async cleanup() {
    try {
      logger.info('Starting retention cleanup', { retentionDays: config.schedule.retentionDays });
      const startTime = Date.now();

      // Get backups older than retention period
      const oldBackups = await manifestManager.getBackups({
        olderThan: config.schedule.retentionDays,
      });

      if (oldBackups.length === 0) {
        logger.info('No backups to clean up');
        return {
          deleted: 0,
          freedSpace: 0,
          duration: 0,
        };
      }

      logger.info('Found backups to clean up', { count: oldBackups.length });

      let deletedCount = 0;
      let freedSpace = 0;
      const errors = [];

      for (const backup of oldBackups) {
        try {
          // Unpin from IPFS
          await ipfsUploader.unpinBackup(backup.cid);
          logger.debug('Unpinned backup from IPFS', { cid: backup.cid, type: backup.type });

          // Delete local backup file if it exists
          if (backup.localPath) {
            try {
              await fs.unlink(backup.localPath);
              logger.debug('Deleted local backup file', { path: backup.localPath });
            } catch (error) {
              // Ignore if file doesn't exist
              if (error.code !== 'ENOENT') {
                logger.warn('Failed to delete local backup file', {
                  path: backup.localPath,
                  error: error.message,
                });
              }
            }
          }

          // Remove from manifest
          await manifestManager.removeBackup(backup.cid);

          deletedCount++;
          freedSpace += backup.size || 0;
        } catch (error) {
          logger.error('Failed to clean up backup', {
            cid: backup.cid,
            error: error.message,
          });
          errors.push({ cid: backup.cid, error: error.message });
        }
      }

      // Clean up local storage directory (remove files older than local retention)
      await this.cleanupLocalStorage();

      // Upload updated manifest
      await manifestManager.uploadManifest();

      const duration = ((Date.now() - startTime) / 1000).toFixed(2);
      logger.info('Retention cleanup completed', {
        deleted: deletedCount,
        freedSpaceMB: (freedSpace / 1024 / 1024).toFixed(2),
        duration: `${duration}s`,
        errors: errors.length,
      });

      return {
        deleted: deletedCount,
        freedSpace,
        duration: parseFloat(duration),
        errors,
      };
    } catch (error) {
      logger.error('Retention cleanup failed', { error: error.message });
      throw error;
    }
  }

  /**
   * Clean up local storage directory
   * @returns {Promise<void>}
   */
  async cleanupLocalStorage() {
    try {
      const storageDir = config.storage.storageDir;
      const localRetentionDays = config.storage.localRetentionDays;

      if (!await fs.access(storageDir).then(() => true).catch(() => false)) {
        return;
      }

      const entries = await fs.readdir(storageDir);
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - localRetentionDays);

      let deletedCount = 0;
      let freedSpace = 0;

      for (const entry of entries) {
        // Skip manifest file
        if (entry === 'manifest.json') {
          continue;
        }

        const entryPath = path.join(storageDir, entry);
        const stats = await fs.stat(entryPath);

        if (stats.mtime < cutoffDate) {
          try {
            const size = stats.size;
            await fs.unlink(entryPath);
            deletedCount++;
            freedSpace += size;
            logger.debug('Deleted old local backup file', {
              path: entryPath,
              age: Math.floor((Date.now() - stats.mtime.getTime()) / (1000 * 60 * 60 * 24)),
            });
          } catch (error) {
            logger.warn('Failed to delete local file', {
              path: entryPath,
              error: error.message,
            });
          }
        }
      }

      if (deletedCount > 0) {
        logger.info('Local storage cleanup completed', {
          deleted: deletedCount,
          freedSpaceMB: (freedSpace / 1024 / 1024).toFixed(2),
        });
      }
    } catch (error) {
      logger.warn('Local storage cleanup failed', { error: error.message });
      // Don't throw - local cleanup failure shouldn't break retention
    }
  }
}

module.exports = new RetentionCleanup();
