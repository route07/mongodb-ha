const cron = require('node-cron');
const backupOrchestrator = require('./backup/orchestrator');
const retentionCleanup = require('./retention/cleanup');
const ipfsClient = require('./ipfs/client');
const config = require('./config/load');
const logger = require('./utils/logger');
const manifestManager = require('./manifest/manager');

class BackupService {
  constructor() {
    this.running = false;
  }

  async start() {
    try {
      logger.info('=== MongoDB IPFS Backup Service Starting ===');
      logger.info('Configuration', config.getSafeConfig());

      // Check IPFS connectivity
      logger.info('Checking IPFS connectivity...');
      const ipfsHealthy = await ipfsClient.checkHealth();
      if (!ipfsHealthy) {
        logger.warn('IPFS health check failed, but continuing...');
      } else {
        logger.info('IPFS nodes are healthy');
      }

      // Load manifest
      await manifestManager.loadManifest();
      const stats = await manifestManager.getStatistics();
      logger.info('Manifest loaded', stats);

      // Schedule backups
      this.scheduleBackups();

      // Schedule retention cleanup (30 minutes after backup)
      cron.schedule('30 2 * * *', async () => {
        await this.runRetentionCleanup();
      });

      logger.info('=== Backup Service Started Successfully ===');
      logger.info('Full backup schedule:', config.schedule.full);
      logger.info('Incremental backup schedule:', config.schedule.incremental);
      logger.info('Retention cleanup schedule: 30 minutes after backup');

      // Keep process alive
      this.running = true;
      process.on('SIGTERM', () => this.stop());
      process.on('SIGINT', () => this.stop());
    } catch (error) {
      logger.error('Failed to start backup service', { error: error.message });
      process.exit(1);
    }
  }

  scheduleBackups() {
    // Schedule full backup
    cron.schedule(config.schedule.full, async () => {
      if (this.running) {
        await this.runFullBackup();
      }
    }, {
      scheduled: true,
      timezone: 'UTC',
    });

    // Schedule incremental backup
    cron.schedule(config.schedule.incremental, async () => {
      if (this.running) {
        await this.runIncrementalBackup();
      }
    }, {
      scheduled: true,
      timezone: 'UTC',
    });

    logger.info('Backups scheduled');
  }

  async runFullBackup() {
    try {
      logger.info('Scheduled full backup triggered');
      await backupOrchestrator.runFullBackup();
    } catch (error) {
      logger.error('Scheduled full backup failed', { error: error.message });
    }
  }

  async runIncrementalBackup() {
    try {
      logger.info('Scheduled incremental backup triggered');
      await backupOrchestrator.runIncrementalBackup();
    } catch (error) {
      logger.error('Scheduled incremental backup failed', { error: error.message });
    }
  }

  async runRetentionCleanup() {
    try {
      logger.info('Scheduled retention cleanup triggered');
      const result = await retentionCleanup.cleanup();
      logger.info('Retention cleanup completed', result);
    } catch (error) {
      logger.error('Scheduled retention cleanup failed', { error: error.message });
    }
  }

  stop() {
    logger.info('Stopping backup service...');
    this.running = false;
    process.exit(0);
  }
}

// Start service if run directly
if (require.main === module) {
  const service = new BackupService();
  service.start().catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
}

module.exports = BackupService;
