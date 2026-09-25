// Configurazione "flat" richiesta da ESLint 9+ (sostituisce .eslintrc.js).
const js = require('@eslint/js');
const globals = require('globals');

module.exports = [
  js.configs.recommended,
  {
    languageOptions: {
      // Le Cloud Functions girano su Node 22: nessun motivo di restare
      // fermi a ES2018 come faceva la vecchia configurazione.
      ecmaVersion: 2022,
      sourceType: 'commonjs',
      globals: {...globals.node},
    },
    rules: {
      'no-restricted-globals': ['error', 'name', 'length'],
      'prefer-arrow-callback': 'error',
      'quotes': ['error', 'single', {avoidEscape: true}],
      'no-unused-vars': ['error', {argsIgnorePattern: '^_'}],
    },
  },
  {
    files: ['**/*.spec.*'],
    languageOptions: {globals: {...globals.mocha}},
  },
];
