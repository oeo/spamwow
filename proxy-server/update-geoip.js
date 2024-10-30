const https = require('https');
const fs = require('fs');
const path = require('path');
const AdmZip = require('adm-zip');

const DB_DIR = path.join(__dirname, 'geoip');
const DB_PATH = path.join(DB_DIR, 'IP2LOCATION-LITE-DB1.BIN');
const DOWNLOAD_URL = 'https://download.ip2location.com/lite/IP2LOCATION-LITE-DB1.BIN.ZIP';

// Ensure directory exists
if (!fs.existsSync(DB_DIR)) {
  fs.mkdirSync(DB_DIR, { recursive: true });
}

console.log('Downloading IP2Location database...');

https.get(DOWNLOAD_URL, (response) => {
  const chunks = [];
  response.on('data', (chunk) => chunks.push(chunk));
  response.on('end', () => {
    const buffer = Buffer.concat(chunks);
    try {
      const zip = new AdmZip(buffer);
      const zipEntries = zip.getEntries();

      // Find the .BIN file in the ZIP
      const dbEntry = zipEntries.find(entry => entry.entryName.endsWith('.BIN'));
      if (!dbEntry) {
        throw new Error('Could not find database file in ZIP');
      }

      // Extract the file
      zip.extractEntryTo(dbEntry, DB_DIR, false, true);
      console.log('IP2Location database updated successfully');
    } catch (err) {
      console.error('Error extracting database:', err);
    }
  });
}).on('error', (err) => {
  console.error('Error downloading IP2Location database:', err);
});
