import { useColorScheme } from 'react-native';
import { catalog, expenseTheme, grouped } from '@/theme/catalog';

export { catalog, expenseTheme, grouped };

export function useScheme(): 'light' | 'dark' {
  return useColorScheme() === 'dark' ? 'dark' : 'light';
}

export function useTokens(): {
  dark: boolean;
  background: string;
  foreground: string;
  card: string;
  cardForeground: string;
  muted: string;
  mutedForeground: string;
  border: string;
  accent: string;
  green: string;
  red: string;
  blue: string;
  expenseBackground: string;
  expenseForeground: string;
  expenseAccent: string;
} {
  const dark = useScheme() === 'dark';
  const mode = dark ? 'dark' : 'light';
  return {
    dark,
    background: catalog.background[mode],
    foreground: catalog.foreground[mode],
    card: catalog.card[mode],
    cardForeground: catalog.cardForeground[mode],
    muted: catalog.muted[mode],
    mutedForeground: catalog.mutedForeground[mode],
    border: catalog.border[mode],
    accent: catalog.accent[mode],
    green: catalog.systemGreen[mode],
    red: catalog.systemRed[mode],
    blue: catalog.systemBlue[mode],
    expenseBackground: expenseTheme.background[mode],
    expenseForeground: expenseTheme.foreground[mode],
    expenseAccent: expenseTheme.accent[mode]
  };
}
