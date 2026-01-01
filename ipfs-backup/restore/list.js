const manifestManager = require('../src/manifest/manager');

async function listBackups(options = {}) {
  const filters = {};
  
  if (options.type) {
    filters.type = options.type;
  }
  
  if (options.since) {
    filters.since = options.since;
  }
  
  if (options.until) {
    filters.until = options.until;
  }

  const backups = await manifestManager.getBackups(filters);
  const stats = await manifestManager.getStatistics();

  console.log('\n=== Available Backups ===\n');
  console.log(`Total: ${stats.totalBackups} backups`);
  console.log(`Total Size: ${(stats.totalSize / 1024 / 1024).toFixed(2)} MB`);
  console.log(`Oldest: ${stats.oldestBackup || 'N/A'}`);
  console.log(`Newest: ${stats.newestBackup || 'N/A'}`);
  console.log('\n=== Backup List ===\n');

  if (backups.length === 0) {
    console.log('No backups found matching criteria.');
    return;
  }

  backups.forEach((backup, index) => {
    console.log(`${index + 1}. ${backup.type.toUpperCase()} Backup`);
    console.log(`   CID: ${backup.cid}`);
    console.log(`   Date: ${backup.timestamp}`);
    console.log(`   Size: ${(backup.size / 1024 / 1024).toFixed(2)} MB`);
    console.log(`   Databases: ${backup.databases.join(', ') || 'all'}`);
    if (backup.type === 'incremental') {
      console.log(`   Base Backup: ${backup.baseBackup}`);
      console.log(`   Oplog Range: ${backup.oplogStart} to ${backup.oplogEnd}`);
    }
    console.log('');
  });
}

module.exports = listBackups;
