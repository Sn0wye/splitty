module.exports = {
  content: ['./app/**/*.{ts,tsx}', './src/**/*.{ts,tsx}'],
  presets: [require('nativewind/preset')],
  theme: {
    extend: {
      colors: {
        background: { DEFAULT: '#F4F4F5', dark: '#09090B' },
        foreground: { DEFAULT: '#18181B', dark: '#F4F4F5' },
        card: { DEFAULT: '#FFFFFF', dark: '#18181B' },
        'card-foreground': { DEFAULT: '#18181B', dark: '#F4F4F5' },
        muted: { DEFAULT: '#E4E4E7', dark: '#27272A' },
        'muted-foreground': { DEFAULT: '#71717A', dark: '#A1A1AA' },
        border: { DEFAULT: '#E4E4E7', dark: '#27272A' },
        accent: { DEFAULT: '#3B82F6', dark: '#3B82F6' },
        'expense-bg': { DEFAULT: '#FEFEFE', dark: '#1C1C1E' },
        'expense-fg': { DEFAULT: '#000000', dark: '#FEFEFE' },
        'expense-accent': { DEFAULT: '#191919', dark: '#F3F3F4' },
        positive: { DEFAULT: '#34C759', dark: '#30D158' },
        negative: { DEFAULT: '#FF3B30', dark: '#FF453A' }
      }
    }
  },
  plugins: []
};
