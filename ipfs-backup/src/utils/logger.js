const fs = require('fs');
const path = require('path');
const config = require('../config/load');

class Logger {
  constructor() {
    this.levels = {
      error: 0,
      warn: 1,
      info: 2,
      debug: 3,
    };
    this.currentLevel = this.levels[config.logging.level] || this.levels.info;
    this.logDir = config.logging.dir;
  }

  log(level, message, data = {}) {
    if (this.levels[level] > this.currentLevel) {
      return;
    }

    const timestamp = new Date().toISOString();
    const logEntry = {
      timestamp,
      level: level.toUpperCase(),
      service: 'mongodb-backup',
      message,
      ...data,
    };

    // Console output
    const consoleMessage = `[${timestamp}] [${level.toUpperCase()}] ${message}`;
    if (level === 'error') {
      console.error(consoleMessage, data);
    } else if (level === 'warn') {
      console.warn(consoleMessage, data);
    } else {
      console.log(consoleMessage, data);
    }

    // File output
    this.writeToFile(logEntry);
  }

  writeToFile(logEntry) {
    try {
      const date = new Date().toISOString().split('T')[0];
      const logFile = path.join(this.logDir, `backup-${date}.log`);
      const logLine = JSON.stringify(logEntry) + '\n';
      fs.appendFileSync(logFile, logLine, { flag: 'a' });
    } catch (error) {
      // Fallback to console if file write fails
      console.error('Failed to write to log file:', error.message);
    }
  }

  error(message, data) {
    this.log('error', message, data);
  }

  warn(message, data) {
    this.log('warn', message, data);
  }

  info(message, data) {
    this.log('info', message, data);
  }

  debug(message, data) {
    this.log('debug', message, data);
  }
}

module.exports = new Logger();
