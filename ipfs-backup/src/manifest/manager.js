const fs = require('fs').promises;
const path = require('path');
const ipfsUploader = require('../ipfs/upload');
const config = require('../config/load');
const logger = require('../utils/logger');

class ManifestManager {
  constructor() {
    this.manifestFile = path.join(config.storage.storageDir, 'manifest.json');
    this.manifest = null;
  }

  /**
   * Load manifest from local file
   * @returns {Promise<object>} - Manifest object
   */
  async loadManifest() {
    try {
      if (await fs.access(this.manifestFile).then(() => true).catch(() => false)) {
        const data = await fs.readFile(this.manifestFile, 'utf8');
        this.manifest = JSON.parse(data);
        logger.debug('Manifest loaded from local file', { 
          backupCount: this.manifest.backups?.length || 0 
        });
      } else {
        // Create new manifest
        this.manifest = {
          version: '1.0',
          createdAt: new Date().toISOString(),
          lastUpdated: new Date().toISOString(),
          manifestCid: null,
          backups: [],
          statistics: {
            totalBackups: 0,
            totalSize: 0,
            oldestBackup: null,
            newestBackup: null,
          },
        };
        logger.debug('Created new manifest');
      }
      return this.manifest;
    } catch (error) {
      logger.error('Failed to load manifest', { error: error.message });
      throw error;
    }
  }

  /**
   * Save manifest to local file
   * @returns {Promise<void>}
   */
  async saveManifest() {
    try {
      this.manifest.lastUpdated = new Date().toISOString();
      await fs.writeFile(
        this.manifestFile,
        JSON.stringify(this.manifest, null, 2),
        'utf8'
      );
      logger.debug('Manifest saved to local file');
    } catch (error) {
      logger.error('Failed to save manifest', { error: error.message });
      throw error;
    }
  }

  /**
   * Upload manifest to IPFS
   * @returns {Promise<string>} - Manifest CID
   */
  async uploadManifest() {
    try {
      // Ensure manifest is saved locally first
      await this.saveManifest();

      // Upload manifest file to IPFS
      const result = await ipfsUploader.uploadFile(this.manifestFile);
      
      // Pin manifest
      await ipfsUploader.pinBackup(result.cid);

      // Update manifest with its own CID
      this.manifest.manifestCid = result.cid;
      await this.saveManifest();

      logger.info('Manifest uploaded to IPFS', { cid: result.cid });
      return result.cid;
    } catch (error) {
      logger.error('Failed to upload manifest to IPFS', { error: error.message });
      throw error;
    }
  }

  /**
   * Add backup to manifest
   * @param {object} backupInfo - Backup information
   * @returns {Promise<void>}
   */
  async addBackup(backupInfo) {
    try {
      await this.loadManifest();

      const backupEntry = {
        type: backupInfo.type,
        cid: backupInfo.cid,
        timestamp: backupInfo.timestamp || new Date().toISOString(),
        size: backupInfo.size,
        encrypted: true,
        duration: backupInfo.duration,
        databases: backupInfo.databases || [],
        mongodbVersion: backupInfo.mongodbVersion || 'unknown',
        replicaSet: backupInfo.replicaSet || config.mongodb.uri.match(/replicaSet=([^&]+)/)?.[1] || 'unknown',
        localPath: backupInfo.localPath, // Path to local backup file
        ...(backupInfo.type === 'incremental' && {
          baseBackup: backupInfo.baseBackup,
          oplogStart: backupInfo.oplogStart,
          oplogEnd: backupInfo.oplogEnd,
        }),
      };

      this.manifest.backups.push(backupEntry);
      this.updateStatistics();

      await this.saveManifest();
      logger.info('Backup added to manifest', { 
        type: backupInfo.type, 
        cid: backupInfo.cid 
      });
    } catch (error) {
      logger.error('Failed to add backup to manifest', { error: error.message });
      throw error;
    }
  }

  /**
   * Remove backup from manifest
   * @param {string} cid - Backup CID to remove
   * @returns {Promise<void>}
   */
  async removeBackup(cid) {
    try {
      await this.loadManifest();

      const index = this.manifest.backups.findIndex(b => b.cid === cid);
      if (index === -1) {
        logger.warn('Backup not found in manifest', { cid });
        return;
      }

      const backup = this.manifest.backups[index];
      this.manifest.backups.splice(index, 1);
      this.updateStatistics();

      await this.saveManifest();
      logger.info('Backup removed from manifest', { cid, type: backup.type });
    } catch (error) {
      logger.error('Failed to remove backup from manifest', { error: error.message });
      throw error;
    }
  }

  /**
   * Get backups matching criteria
   * @param {object} filters - Filter criteria
   * @returns {Promise<Array>} - Matching backups
   */
  async getBackups(filters = {}) {
    try {
      await this.loadManifest();

      let backups = [...this.manifest.backups];

      if (filters.type) {
        backups = backups.filter(b => b.type === filters.type);
      }

      if (filters.since) {
        const sinceDate = new Date(filters.since);
        backups = backups.filter(b => new Date(b.timestamp) >= sinceDate);
      }

      if (filters.until) {
        const untilDate = new Date(filters.until);
        backups = backups.filter(b => new Date(b.timestamp) <= untilDate);
      }

      if (filters.olderThan) {
        const cutoffDate = new Date();
        cutoffDate.setDate(cutoffDate.getDate() - filters.olderThan);
        backups = backups.filter(b => new Date(b.timestamp) < cutoffDate);
      }

      // Sort by timestamp (newest first)
      backups.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));

      return backups;
    } catch (error) {
      logger.error('Failed to get backups', { error: error.message });
      throw error;
    }
  }

  /**
   * Get latest full backup
   * @returns {Promise<object|null>} - Latest full backup or null
   */
  async getLatestFullBackup() {
    try {
      const fullBackups = await this.getBackups({ type: 'full' });
      return fullBackups.length > 0 ? fullBackups[0] : null;
    } catch (error) {
      logger.error('Failed to get latest full backup', { error: error.message });
      throw error;
    }
  }

  /**
   * Update manifest statistics
   */
  updateStatistics() {
    if (!this.manifest || !this.manifest.backups) {
      return;
    }

    const backups = this.manifest.backups;
    this.manifest.statistics = {
      totalBackups: backups.length,
      totalSize: backups.reduce((sum, b) => sum + (b.size || 0), 0),
      oldestBackup: backups.length > 0 
        ? backups.reduce((oldest, b) => 
            new Date(b.timestamp) < new Date(oldest.timestamp) ? b : oldest
          ).timestamp
        : null,
      newestBackup: backups.length > 0
        ? backups.reduce((newest, b) => 
            new Date(b.timestamp) > new Date(newest.timestamp) ? b : newest
          ).timestamp
        : null,
    };
  }

  /**
   * Get manifest statistics
   * @returns {Promise<object>} - Manifest statistics
   */
  async getStatistics() {
    try {
      await this.loadManifest();
      this.updateStatistics();
      return this.manifest.statistics;
    } catch (error) {
      logger.error('Failed to get statistics', { error: error.message });
      throw error;
    }
  }
}

module.exports = new ManifestManager();
