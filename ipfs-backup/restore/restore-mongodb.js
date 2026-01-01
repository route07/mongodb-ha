const { exec } = require('child_process');
const { promisify } = require('util');
const config = require('../src/config/load');
const logger = require('../src/utils/logger');

const execAsync = promisify(exec);

async function restoreBackup(backupDir, mongoUri, drop = false) {
  console.log(`Restoring from ${backupDir}...`);
  
  try {
    const args = [
      '--uri', mongoUri,
      backupDir,
    ];

    if (drop) {
      args.push('--drop');
    }

    // Add gzip flag if backup is compressed
    args.push('--gzip');

    const command = `${config.mongodbTools.mongorestore} ${args.join(' ')}`;
    logger.debug('Executing mongorestore', { command: command.replace(/:[^:@]+@/, ':****@') });

    const { stdout, stderr } = await execAsync(command, {
      maxBuffer: 10 * 1024 * 1024,
    });

    if (stderr && !stderr.includes('done') && !stderr.includes('restoring')) {
      console.warn('mongorestore warnings:', stderr);
    }

    console.log('✓ Restore completed successfully!');
    if (stdout) {
      console.log(stdout);
    }
  } catch (error) {
    throw new Error(`Failed to restore backup: ${error.message}`);
  }
}

module.exports = restoreBackup;
