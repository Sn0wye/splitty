import { useTokens } from '@/theme/tokens';

export function useNavigationColors(): {
  dark: boolean;
  tint: string;
  background: string;
  card: string;
  tabInactive: string;
  border: string;
} {
  const tokens = useTokens();
  return {
    dark: tokens.dark,
    tint: tokens.accent,
    background: tokens.background,
    card: tokens.card,
    tabInactive: tokens.mutedForeground,
    border: tokens.border
  };
}
