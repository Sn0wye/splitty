import React from 'react';
import { Dimensions, View } from 'react-native';
import { Stack } from 'expo-router';
import { ExpenseFormProvider, useExpenseFormState } from '@/expense/ExpenseFormContext';
import { Loading } from '@/components/Screen';
import { ErrorMessage } from '@/components/UI';
import { useReducedMotion } from '@/hooks/useReducedMotion';
import { expenseDateSheetDetent } from '@/nav/dateSheet';
import { useTokens } from '@/theme/tokens';

function ExpenseStack(): React.JSX.Element {
  const tokens = useTokens();
  const reduced = useReducedMotion();
  const state = useExpenseFormState();
  if (state.status === 'loading') return <Loading />;
  if (state.status === 'error') {
    return <View style={{ flex: 1, padding: 20, backgroundColor: tokens.expenseBackground }}><ErrorMessage message={state.message} /></View>;
  }
  return (
    <Stack screenOptions={{
      headerBackTitle: 'Back',
      headerTintColor: tokens.expenseForeground,
      headerShadowVisible: false,
      headerStyle: { backgroundColor: tokens.expenseBackground },
      contentStyle: { backgroundColor: tokens.expenseBackground },
      animation: reduced ? 'fade' : 'slide_from_right',
      animationDuration: reduced ? 200 : 350
    }}>
      <Stack.Screen name="index" options={{ title: '' }} />
      <Stack.Screen name="details" options={{ title: '' }} />
      <Stack.Screen name="split" options={{ title: 'Split' }} />
      <Stack.Screen name="payer" options={{ title: 'Paid by' }} />
      <Stack.Screen name="date" options={{
        title: '',
        headerShown: false,
        presentation: 'formSheet',
        sheetAllowedDetents: [expenseDateSheetDetent(Dimensions.get('window').height)],
        sheetCornerRadius: 28,
        contentStyle: { backgroundColor: tokens.expenseBackground }
      }} />
    </Stack>
  );
}

export default function NewExpenseLayout(): React.JSX.Element {
  return (
    <ExpenseFormProvider>
      <ExpenseStack />
    </ExpenseFormProvider>
  );
}
