import React from 'react';
import { Stack } from 'expo-router';
import { useNavigationColors } from '@/nav/theme';
import { useTokens } from '@/theme/tokens';

export default function GroupStack(): React.JSX.Element {
  const colors = useNavigationColors();
  const tokens = useTokens();
  return (
    <Stack screenOptions={{
      headerBackButtonDisplayMode: 'minimal',
      headerTintColor: colors.tint,
      headerTitleStyle: { color: tokens.foreground },
      headerShadowVisible: false,
      headerStyle: { backgroundColor: colors.background },
      contentStyle: { backgroundColor: colors.background }
    }}>
      <Stack.Screen name="index" options={{ headerShown: false }} />
      <Stack.Screen name="[id]" options={{ headerShown: false }} />
      <Stack.Screen name="[id]/balances" options={{
        title: 'Balances',
        presentation: 'formSheet',
        sheetAllowedDetents: [0.5, 1],
        sheetGrabberVisible: true
      }} />
      <Stack.Screen name="[id]/settle" options={{ title: 'Settle up', presentation: 'modal' }} />
      <Stack.Screen name="[id]/new-expense" options={{
        title: '',
        presentation: 'formSheet',
        sheetAllowedDetents: [1],
        sheetCornerRadius: 28,
        sheetGrabberVisible: false,
        headerShown: false,
        contentStyle: { backgroundColor: tokens.expenseBackground }
      }} />
      <Stack.Screen name="[id]/expense/[expenseId]" options={{ title: 'Expense' }} />
      <Stack.Screen name="[id]/manage" options={{ title: 'Edit group', presentation: 'modal' }} />
    </Stack>
  );
}
