const { createGzip } = require('zlib');
const { createReadStream, createWriteStream } = require('fs');
const { pipeline } = require('stream/promises');
const path = require('path');
const logger = require('./logger');

class Compression {
  /**
   * Compress a directory to a tar.gz file
   * @param {string} sourceDir - Directory to compress
   * @param {string} outputFile - Output tar.gz file path
   * @returns {Promise<string>} - Path to compressed file
   */
  async compressDirectory(sourceDir, outputFile) {
    const tar = require('tar');
    
    try {
      logger.debug('Compressing directory', { sourceDir, outputFile });
      
      await tar.create(
        {
          gzip: true,
          file: outputFile,
          cwd: path.dirname(sourceDir),
        },
        [path.basename(sourceDir)]
      );

      logger.debug('Compression completed', { outputFile });
      return outputFile;
    } catch (error) {
      logger.error('Compression failed', { error: error.message, sourceDir, outputFile });
      throw error;
    }
  }

  /**
   * Compress a single file with gzip
   * @param {string} inputFile - File to compress
   * @param {string} outputFile - Output gzip file path
   * @returns {Promise<string>} - Path to compressed file
   */
  async compressFile(inputFile, outputFile) {
    try {
      logger.debug('Compressing file', { inputFile, outputFile });
      
      const gzip = createGzip({ level: 6 });
      const source = createReadStream(inputFile);
      const destination = createWriteStream(outputFile);

      await pipeline(source, gzip, destination);

      logger.debug('File compression completed', { outputFile });
      return outputFile;
    } catch (error) {
      logger.error('File compression failed', { error: error.message, inputFile, outputFile });
      throw error;
    }
  }

  /**
   * Extract a tar.gz file
   * @param {string} archiveFile - tar.gz file to extract
   * @param {string} outputDir - Directory to extract to
   * @returns {Promise<string>} - Path to extracted directory
   */
  async extractArchive(archiveFile, outputDir) {
    const tar = require('tar');
    
    try {
      logger.debug('Extracting archive', { archiveFile, outputDir });
      
      await tar.extract({
        file: archiveFile,
        cwd: outputDir,
      });

      logger.debug('Extraction completed', { outputDir });
      return outputDir;
    } catch (error) {
      logger.error('Extraction failed', { error: error.message, archiveFile, outputDir });
      throw error;
    }
  }
}

module.exports = new Compression();
