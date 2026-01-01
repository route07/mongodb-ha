const { create } = require('ipfs-http-client');
const config = require('../config/load');
const logger = require('../utils/logger');

class IPFSClient {
  constructor() {
    this.clients = [];
    this.init();
  }

  init() {
    try {
      // Create client for each IPFS node
      if (config.ipfs.node1Url) {
        const client1 = create({ url: config.ipfs.node1Url });
        this.clients.push({ client: client1, url: config.ipfs.node1Url, node: 1 });
        logger.info('IPFS client initialized', { node: 1, url: config.ipfs.node1Url });
      }

      if (config.ipfs.node2Url) {
        const client2 = create({ url: config.ipfs.node2Url });
        this.clients.push({ client: client2, url: config.ipfs.node2Url, node: 2 });
        logger.info('IPFS client initialized', { node: 2, url: config.ipfs.node2Url });
      }

      if (this.clients.length === 0) {
        throw new Error('No IPFS nodes configured');
      }
    } catch (error) {
      logger.error('Failed to initialize IPFS clients', { error: error.message });
      throw error;
    }
  }

  /**
   * Get primary client (first node)
   * @returns {object} - IPFS client
   */
  getPrimaryClient() {
    if (this.clients.length === 0) {
      throw new Error('No IPFS clients available');
    }
    return this.clients[0].client;
  }

  /**
   * Get all clients
   * @returns {Array} - Array of IPFS clients
   */
  getAllClients() {
    return this.clients;
  }

  /**
   * Check if IPFS nodes are accessible
   * @returns {Promise<boolean>} - True if all nodes are accessible
   */
  async checkHealth() {
    try {
      const results = await Promise.all(
        this.clients.map(async ({ client, node }) => {
          try {
            const id = await client.id();
            logger.debug('IPFS node health check', { node, id: id.id });
            return { node, healthy: true };
          } catch (error) {
            logger.warn('IPFS node health check failed', { node, error: error.message });
            return { node, healthy: false, error: error.message };
          }
        })
      );

      const allHealthy = results.every(r => r.healthy);
      return allHealthy;
    } catch (error) {
      logger.error('IPFS health check failed', { error: error.message });
      return false;
    }
  }
}

module.exports = new IPFSClient();
