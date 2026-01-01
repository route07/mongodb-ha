#!/usr/bin/env node

/**
 * Manual backup trigger script
 * Usage: node scripts/manual-backup.js [full|incremental]
 */

const backupOrchestrator = require('../src/backup/orchestrator');

async function main() {
  const type = process.argv[2] || 'full';

  if (type !== 'full' && type !== 'incremental') {
    console.error('Usage: node scripts/manual-backup.js [full|incremental]');
    process.exit(1);
  }

  try {
    console.log(`Starting manual ${type} backup...`);
    
    let result;
    if (type === 'full') {
      result = await backupOrchestrator.runFullBackup();
    } else {
      result = await backupOrchestrator.runIncrementalBackup();
    }

    console.log('\n✓ Backup completed successfully!');
    console.log(`CID: ${result.cid}`);
    console.log(`Size: ${(result.size / 1024 / 1024).toFixed(2)} MB`);
    console.log(`Duration: ${result.duration.toFixed(2)}s`);
    
    process.exit(0);
  } catch (error) {
    console.error('\n✗ Backup failed:', error.message);
    process.exit(1);
  }
}

main();
