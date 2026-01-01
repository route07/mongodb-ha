const encryption = require('../src/encryption/encrypt');

async function decryptBackup(encryptedFile, outputFile) {
  console.log(`Decrypting ${encryptedFile}...`);
  
  try {
    await encryption.decryptFile(encryptedFile, outputFile);
    console.log(`✓ Decrypted: ${outputFile}`);
    return outputFile;
  } catch (error) {
    throw new Error(`Failed to decrypt backup: ${error.message}`);
  }
}

module.exports = decryptBackup;
