#!/usr/bin/env node

const { program } = require('commander');
const listBackups = require('./list');
const downloadBackup = require('./download');
const decryptBackup = require('./decrypt');
const restoreBackup = require('./restore-mongodb');

program
  .name('mongodb-restore')
  .description('MongoDB backup restore tool for IPFS backups')
  .version('1.0.0');

program
  .command('list')
  .description('List available backups')
  .option('-t, --type <type>', 'Filter by type (full|incremental)')
  .option('-s, --since <date>', 'Show backups since date (YYYY-MM-DD)')
  .option('-u, --until <date>', 'Show backups until date (YYYY-MM-DD)')
  .action(async (options) => {
    try {
      await listBackups(options);
    } catch (error) {
      console.error('Error:', error.message);
      process.exit(1);
    }
  });

program
  .command('download <cid>')
  .description('Download backup from IPFS by CID')
  .option('-o, --output <path>', 'Output file path', 'backup.tar.gz.enc')
  .action(async (cid, options) => {
    try {
      await downloadBackup(cid, options.output);
    } catch (error) {
      console.error('Error:', error.message);
      process.exit(1);
    }
  });

program
  .command('decrypt <encrypted-file>')
  .description('Decrypt backup file')
  .option('-o, --output <path>', 'Output file path', 'backup.tar.gz')
  .action(async (encryptedFile, options) => {
    try {
      await decryptBackup(encryptedFile, options.output);
    } catch (error) {
      console.error('Error:', error.message);
      process.exit(1);
    }
  });

program
  .command('restore <backup-dir>')
  .description('Restore backup to MongoDB')
  .requiredOption('-u, --uri <uri>', 'MongoDB connection URI')
  .option('--drop', 'Drop existing collections before restore', false)
  .action(async (backupDir, options) => {
    try {
      await restoreBackup(backupDir, options.uri, options.drop);
    } catch (error) {
      console.error('Error:', error.message);
      process.exit(1);
    }
  });

program
  .command('restore-full <full-backup-cid>')
  .description('Full restore workflow: download, decrypt, extract, restore')
  .requiredOption('-u, --uri <uri>', 'MongoDB connection URI')
  .option('--drop', 'Drop existing collections before restore', false)
  .option('--keep-files', 'Keep downloaded and decrypted files', false)
  .action(async (cid, options) => {
    try {
      const path = require('path');
      const fs = require('fs').promises;
      const tempDir = path.join(process.cwd(), 'restore-temp');
      await fs.mkdir(tempDir, { recursive: true });

      console.log('Step 1/4: Downloading from IPFS...');
      const encryptedFile = path.join(tempDir, 'backup.tar.gz.enc');
      await downloadBackup(cid, encryptedFile);

      console.log('Step 2/4: Decrypting backup...');
      const decryptedFile = path.join(tempDir, 'backup.tar.gz');
      await decryptBackup(encryptedFile, decryptedFile);

      console.log('Step 3/4: Extracting backup...');
      const extractDir = path.join(tempDir, 'extracted');
      await fs.mkdir(extractDir, { recursive: true });
      const compression = require('../src/utils/compression');
      await compression.extractArchive(decryptedFile, extractDir);

      console.log('Step 4/4: Restoring to MongoDB...');
      // Find the actual backup directory (mongodump creates a directory structure)
      const entries = await fs.readdir(extractDir);
      const backupDir = entries.find(e => {
        const fullPath = path.join(extractDir, e);
        return fs.stat(fullPath).then(s => s.isDirectory()).catch(() => false);
      });
      
      if (!backupDir) {
        throw new Error('Could not find backup directory in extracted files');
      }

      await restoreBackup(path.join(extractDir, backupDir), options.uri, options.drop);

      if (!options.keepFiles) {
        console.log('Cleaning up temporary files...');
        await fs.rm(tempDir, { recursive: true, force: true });
      } else {
        console.log(`Temporary files kept in: ${tempDir}`);
      }

      console.log('✓ Full restore completed successfully!');
    } catch (error) {
      console.error('Error:', error.message);
      process.exit(1);
    }
  });

program.parse();
