const crypto = require('crypto');
const fs = require('fs');
const { createReadStream, createWriteStream } = require('fs');
const { pipeline } = require('stream/promises');
const config = require('../config/load');
const logger = require('../utils/logger');

class Encryption {
  /**
   * Get encryption key from config (base64 decoded)
   * @returns {Buffer} - 32-byte encryption key
   */
  getKey() {
    const keyBase64 = config.encryption.key;
    const key = Buffer.from(keyBase64, 'base64');
    
    if (key.length !== 32) {
      throw new Error('Encryption key must be 32 bytes (256 bits)');
    }
    
    return key;
  }

  /**
   * Encrypt a file using AES-256-GCM
   * @param {string} inputPath - Path to file to encrypt
   * @param {string} outputPath - Path to save encrypted file
   * @returns {Promise<string>} - Path to encrypted file
   */
  async encryptFile(inputPath, outputPath) {
    try {
      logger.debug('Encrypting file', { inputPath, outputPath });
      
      const key = this.getKey();
      const iv = crypto.randomBytes(12); // 12 bytes for GCM
      const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);

      const input = createReadStream(inputPath);
      const output = createWriteStream(outputPath);

      // Write IV first (12 bytes)
      output.write(iv);

      // Encrypt and write data
      input.on('data', (chunk) => {
        const encrypted = cipher.update(chunk);
        output.write(encrypted);
      });

      input.on('end', () => {
        const final = cipher.final();
        output.write(final);
        
        // Write auth tag (16 bytes)
        const authTag = cipher.getAuthTag();
        output.write(authTag);
        
        output.end();
      });

      await new Promise((resolve, reject) => {
        output.on('finish', resolve);
        output.on('error', reject);
        input.on('error', reject);
      });

      logger.debug('File encrypted successfully', { outputPath });
      return outputPath;
    } catch (error) {
      logger.error('Encryption failed', { error: error.message, inputPath });
      throw error;
    }
  }

  /**
   * Encrypt file using streams (more memory efficient for large files)
   * @param {string} inputPath - Path to file to encrypt
   * @param {string} outputPath - Path to save encrypted file
   * @returns {Promise<string>} - Path to encrypted file
   */
  async encryptFileStream(inputPath, outputPath) {
    try {
      logger.debug('Encrypting file with streams', { inputPath, outputPath });
      
      const key = this.getKey();
      const iv = crypto.randomBytes(12);
      const cipher = crypto.createCipheriv('aes-256-gcm', key, iv);

      const input = createReadStream(inputPath);
      const output = createWriteStream(outputPath);

      // Write IV first
      output.write(iv);

      // Create transform stream for encryption
      const encryptStream = input.pipe(cipher);

      // Write encrypted data
      encryptStream.pipe(output, { end: false });

      encryptStream.on('end', () => {
        // Write auth tag
        const authTag = cipher.getAuthTag();
        output.write(authTag);
        output.end();
      });

      await new Promise((resolve, reject) => {
        output.on('finish', resolve);
        output.on('error', reject);
        encryptStream.on('error', reject);
        input.on('error', reject);
      });

      logger.debug('File encrypted successfully', { outputPath });
      return outputPath;
    } catch (error) {
      logger.error('Encryption failed', { error: error.message, inputPath });
      throw error;
    }
  }

  /**
   * Decrypt a file
   * @param {string} inputPath - Path to encrypted file
   * @param {string} outputPath - Path to save decrypted file
   * @returns {Promise<string>} - Path to decrypted file
   */
  async decryptFile(inputPath, outputPath) {
    try {
      logger.debug('Decrypting file', { inputPath, outputPath });
      
      const key = this.getKey();
      const fileStats = fs.statSync(inputPath);
      const fileHandle = fs.openSync(inputPath, 'r');

      // Read IV (first 12 bytes)
      const iv = Buffer.alloc(12);
      fs.readSync(fileHandle, iv, 0, 12, 0);

      // Read auth tag (last 16 bytes)
      const authTag = Buffer.alloc(16);
      fs.readSync(fileHandle, authTag, 0, 16, fileStats.size - 16);

      const decipher = crypto.createDecipheriv('aes-256-gcm', key, iv);
      decipher.setAuthTag(authTag);

      const input = createReadStream(inputPath, { start: 12, end: fileStats.size - 17 });
      const output = createWriteStream(outputPath);

      input.pipe(decipher).pipe(output);

      await new Promise((resolve, reject) => {
        output.on('finish', resolve);
        output.on('error', reject);
        decipher.on('error', reject);
        input.on('error', reject);
      });

      fs.closeSync(fileHandle);

      logger.debug('File decrypted successfully', { outputPath });
      return outputPath;
    } catch (error) {
      logger.error('Decryption failed', { error: error.message, inputPath });
      throw error;
    }
  }
}

module.exports = new Encryption();
