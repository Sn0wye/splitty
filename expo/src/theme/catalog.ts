/** Catalog colors from Splitty/Assets.xcassets (light / dark). */
export const catalog = {
  background: { light: '#F4F4F5', dark: '#09090B' },
  foreground: { light: '#18181B', dark: '#F4F4F5' },
  card: { light: '#FFFFFF', dark: '#18181B' },
  cardForeground: { light: '#18181B', dark: '#F4F4F5' },
  muted: { light: '#E4E4E7', dark: '#27272A' },
  mutedForeground: { light: '#71717A', dark: '#A1A1AA' },
  border: { light: '#E4E4E7', dark: '#27272A' },
  accent: { light: '#3B82F6', dark: '#3B82F6' },
  black: '#000000',
  white: '#FFFFFF',
  systemGreen: { light: '#34C759', dark: '#30D158' },
  systemRed: { light: '#FF3B30', dark: '#FF453A' },
  systemBlue: { light: '#007AFF', dark: '#0A84FF' }
} as const;

/** Inset-grouped Form/List geometry from Swift (20pt side inset, 10pt corners). */
export const grouped = {
  sideInset: 20,
  cornerRadius: 10
} as const;

/** Expense sheet palette from ExpenseTheme.swift — not the catalog. */
export const expenseTheme = {
  background: { light: '#FEFEFE', dark: '#1C1C1E' },
  foreground: { light: '#000000', dark: '#FEFEFE' },
  accent: { light: '#191919', dark: '#F3F3F4' }
} as const;
