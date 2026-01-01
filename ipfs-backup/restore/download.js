const { create } = require('ipfs-http-client');
const fs = require('fs');
const path = require('path');
const config = require('../src/config/load');

async function downloadBackup(cid, outputPath) {
  console.log(`Downloading backup ${cid}...`);
  
  try {
    // Use first IPFS node
    const ipfs = create({ url: config.ipfs.node1Url });
    
    // Get file from IPFS
    const chunks = [];
    for await (const chunk of ipfs.cat(cid)) {
      chunks.push(chunk);
    }
    
    const fileContent = Buffer.concat(chunks);
    
    // Ensure output directory exists
    const outputDir = path.dirname(outputPath);
    if (outputDir && !fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }
    
    // Write file
    fs.writeFileSync(outputPath, fileContent);
    
    const stats = fs.statSync(outputPath);
    console.log(`✓ Downloaded: ${outputPath}`);
    console.log(`  Size: ${(stats.size / 1024 / 1024).toFixed(2)} MB`);
    
    return outputPath;
  } catch (error) {
    throw new Error(`Failed to download backup: ${error.message}`);
  }
}

module.exports = downloadBackup;
