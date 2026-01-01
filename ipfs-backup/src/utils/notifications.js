const axios = require('axios');
const config = require('../config/load');
const logger = require('./logger');

class Notifications {
  /**
   * Send webhook notification
   * @param {string} type - Notification type (success, error, warning)
   * @param {string} title - Notification title
   * @param {object} data - Additional data
   */
  async sendWebhook(type, title, data = {}) {
    if (!config.notifications.enabled || !config.notifications.webhookUrl) {
      logger.debug('Webhook notifications disabled or URL not configured');
      return;
    }

    try {
      const payload = {
        type,
        title,
        timestamp: new Date().toISOString(),
        service: 'mongodb-backup',
        ...data,
      };

      logger.debug('Sending webhook notification', { type, title });
      
      await axios.post(config.notifications.webhookUrl, payload, {
        timeout: 10000,
        headers: {
          'Content-Type': 'application/json',
        },
      });

      logger.debug('Webhook notification sent successfully');
    } catch (error) {
      logger.warn('Failed to send webhook notification', {
        error: error.message,
        type,
        title,
      });
      // Don't throw - notification failure shouldn't break backup
    }
  }

  /**
   * Send backup success notification
   */
  async backupSuccess(backupInfo) {
    await this.sendWebhook('success', 'Backup Completed Successfully', {
      backupType: backupInfo.type,
      cid: backupInfo.cid,
      size: backupInfo.size,
      duration: backupInfo.duration,
    });
  }

  /**
   * Send backup failure notification
   */
  async backupFailure(error, backupType) {
    await this.sendWebhook('error', 'Backup Failed', {
      backupType,
      error: error.message,
      stack: error.stack,
    });
  }

  /**
   * Send retention cleanup notification
   */
  async retentionCleanup(deletedCount, freedSpace) {
    await this.sendWebhook('info', 'Retention Cleanup Completed', {
      deletedBackups: deletedCount,
      freedSpace,
    });
  }
}

module.exports = new Notifications();
