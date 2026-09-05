module.exports = {
  extends: 'expo',
  parser: '@typescript-eslint/parser',
  parserOptions: { project: './tsconfig.json' },
  plugins: ['@typescript-eslint'],
  ignorePatterns: ['node_modules', 'ios', 'android', 'dist', '.expo'],
  rules: { '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }] }
};
