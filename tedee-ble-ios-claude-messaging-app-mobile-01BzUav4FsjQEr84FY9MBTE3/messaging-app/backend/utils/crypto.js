const crypto = require('crypto');

/**
 * Genera userId da chiave pubblica usando SHA-256
 * @param {string} publicKey - La chiave pubblica in formato PEM o base64
 * @returns {string} - Hash SHA-256 in formato hex
 */
function generateUserId(publicKey) {
  return crypto.createHash('sha256').update(publicKey).digest('hex');
}

module.exports = { generateUserId };
