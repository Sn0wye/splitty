import '../global.css';
import React, { useMemo } from 'react';
import { DarkTheme, DefaultTheme, Stack, ThemeProvider } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { AuthProvider } from '@/auth/AuthContext';
import { LastGroupProvider } from '@/nav/LastGroupContext';
import { useNavigationColors } from '@/nav/theme';
import { useTokens } from '@/theme/tokens';

export const unstable_settings = { anchor: 'index' };

export default function RootLayout(): React.JSX.Element {
  const colors = useNavigationColors();
  const tokens = useTokens();
  const navigationTheme = useMemo(() => {
    const base = colors.dark ? DarkTheme : DefaultTheme;
    return {
      ...base,
      colors: {
        ...base.colors,
        primary: colors.tint,
        background: colors.background,
        card: colors.card,
        text: tokens.foreground,
        border: colors.border,
        notification: tokens.red
      }
    };
  }, [colors.background, colors.border, colors.card, colors.dark, colors.tint, tokens.foreground, tokens.red]);
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <AuthProvider>
        <LastGroupProvider>
          <ThemeProvider value={navigationTheme}>
            <StatusBar style={colors.dark ? 'light' : 'dark'} />
            <Stack screenOptions={{
              headerBackTitle: 'Back',
              headerTintColor: colors.tint,
              headerShadowVisible: false,
              headerStyle: { backgroundColor: colors.background },
              contentStyle: { backgroundColor: colors.background }
            }}>
              <Stack.Screen name="index" options={{ headerShown: false }} />
              <Stack.Screen name="login" options={{ headerShown: false }} />
              <Stack.Screen name="(tabs)" options={{ headerShown: false }} />
              <Stack.Screen name="new-group" options={{ title: 'New group', presentation: 'modal' }} />
              <Stack.Screen name="join" options={{ title: 'Join with code', presentation: 'modal' }} />
            </Stack>
          </ThemeProvider>
        </LastGroupProvider>
      </AuthProvider>
    </GestureHandlerRootView>
  );
}
