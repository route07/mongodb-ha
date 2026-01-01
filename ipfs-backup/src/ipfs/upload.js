const fs = require('fs');
const path = require('path');
const ipfsClient = require('./client');
const config = require('../config/load');
const logger = require('../utils/logger');

class IPFSUploader {
  /**
   * Upload file to IPFS and pin on all nodes
   * @param {string} filePath - Path to file to upload
   * @returns {Promise<object>} - Upload result with CID and pin status
   */
  async uploadFile(filePath) {
    try {
      logger.info('Uploading file to IPFS', { filePath });
      const startTime = Date.now();

      // Verify file exists
      if (!fs.existsSync(filePath)) {
        throw new Error(`File not found: ${filePath}`);
      }

      const fileStats = fs.statSync(filePath);
      logger.debug('File stats', { 
        path: filePath, 
        size: fileStats.size,
        sizeMB: (fileStats.size / 1024 / 1024).toFixed(2)
      });

      // Use primary client to add file
      const primaryClient = await ipfsClient.getPrimaryClient();
      
      // Read file
      const fileContent = fs.readFileSync(filePath);
      const file = {
        path: path.basename(filePath),
        content: fileContent,
      };

      // Add to IPFS
      const result = await primaryClient.add(file, {
        pin: false, // We'll pin manually on all nodes
        cidVersion: 1,
      });

      const cid = result.cid.toString();
      logger.info('File added to IPFS', { cid, filePath });

      // Pin on all nodes
      const pinResults = await this.pinBackup(cid);

      const duration = ((Date.now() - startTime) / 1000).toFixed(2);
      logger.info('File upload completed', { 
        cid, 
        duration: `${duration}s`,
        pinned: pinResults.every(p => p.success)
      });

      return {
        cid,
        size: fileStats.size,
        duration: parseFloat(duration),
        pinResults,
      };
    } catch (error) {
      logger.error('IPFS upload failed', { error: error.message, filePath });
      throw error;
    }
  }

  /**
   * Pin backup on all IPFS nodes
   * @param {string} cid - Content ID to pin
   * @returns {Promise<Array>} - Pin results for each node
   */
  async pinBackup(cid) {
    const clients = await ipfsClient.getAllClients();
    const pinResults = [];

    logger.debug('Pinning backup on all nodes', { cid, nodeCount: clients.length });

    for (const { client, node, url } of clients) {
      try {
        await client.pin.add(cid, { timeout: 30000 });
        logger.debug('Backup pinned successfully', { cid, node, url });
        pinResults.push({ node, success: true, url });
      } catch (error) {
        logger.warn('Failed to pin backup on node', { 
          cid, 
          node, 
          url, 
          error: error.message 
        });
        pinResults.push({ node, success: false, url, error: error.message });
      }
    }

    // Verify we have at least the required replication factor
    const successCount = pinResults.filter(r => r.success).length;
    if (successCount < config.ipfs.replicationFactor) {
      throw new Error(
        `Failed to pin on required number of nodes. ` +
        `Required: ${config.ipfs.replicationFactor}, Pinned: ${successCount}`
      );
    }

    return pinResults;
  }

  /**
   * Verify backup is pinned on all nodes
   * @param {string} cid - Content ID to verify
   * @returns {Promise<object>} - Verification results
   */
  async verifyPin(cid) {
    const clients = await ipfsClient.getAllClients();
    const results = [];

    for (const { client, node, url } of clients) {
      try {
        const pins = await client.pin.ls({ timeout: 10000 });
        const pinned = Array.from(pins).some(pin => pin.cid.toString() === cid);
        results.push({ node, url, pinned });
        
        if (pinned) {
          logger.debug('Backup verified on node', { cid, node, url });
        } else {
          logger.warn('Backup not found on node', { cid, node, url });
        }
      } catch (error) {
        logger.warn('Failed to verify pin on node', { 
          cid, 
          node, 
          url, 
          error: error.message 
        });
        results.push({ node, url, pinned: false, error: error.message });
      }
    }

    const allPinned = results.every(r => r.pinned);
    return {
      cid,
      allPinned,
      results,
    };
  }

  /**
   * Unpin backup from all nodes
   * @param {string} cid - Content ID to unpin
   * @returns {Promise<Array>} - Unpin results
   */
  async unpinBackup(cid) {
    const clients = await ipfsClient.getAllClients();
    const results = [];

    logger.info('Unpinning backup from all nodes', { cid });

    for (const { client, node, url } of clients) {
      try {
        await client.pin.rm(cid, { timeout: 30000 });
        logger.debug('Backup unpinned successfully', { cid, node, url });
        results.push({ node, success: true, url });
      } catch (error) {
        // Ignore "not pinned" errors
        if (error.message.includes('not pinned')) {
          logger.debug('Backup already unpinned', { cid, node, url });
          results.push({ node, success: true, url, note: 'already unpinned' });
        } else {
          logger.warn('Failed to unpin backup on node', { 
            cid, 
            node, 
            url, 
            error: error.message 
          });
          results.push({ node, success: false, url, error: error.message });
        }
      }
    }

    return results;
  }
}

module.exports = new IPFSUploader();
