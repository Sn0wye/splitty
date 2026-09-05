import React from 'react';
import { Platform, View } from 'react-native';
import DateTimePicker from '@react-native-community/datetimepicker';
import { router } from 'expo-router';
import { PressableScale } from '@/components/PressableScale';
import { Symbol } from '@/components/Symbol';
import { useExpenseForm } from '@/expense/ExpenseFormContext';
import { useTokens } from '@/theme/tokens';

export default function ExpenseDate(): React.JSX.Element {
  const tokens = useTokens();
  const form = useExpenseForm();
  if (Platform.OS === 'android') {
    return (
      <DateTimePicker
        value={form.date}
        mode="date"
        display="default"
        accentColor={tokens.expenseAccent}
        onChange={(_event, next) => {
          router.back();
          if (next) form.setDate(next);
        }}
      />
    );
  }
  return (
    <View style={{ flex: 1, padding: 20, backgroundColor: tokens.expenseBackground }}>
      <DateTimePicker
        value={form.date}
        mode="date"
        display="inline"
        accentColor={tokens.expenseAccent}
        themeVariant={tokens.dark ? 'dark' : 'light'}
        testID="expense.datePicker"
        accessibilityLabel="Date"
        onChange={(_event, next) => { if (next) form.setDate(next); }}
      />
      <PressableScale accessibilityRole="button" accessibilityLabel="done" onPress={() => router.back()} style={{ marginTop: 16, alignItems: 'center' }}>
        <View style={{ height: 44, width: 44, alignItems: 'center', justifyContent: 'center', borderRadius: 22, backgroundColor: tokens.expenseAccent }}>
          <Symbol sf="arrow.right" ion="arrow-forward" size={18} color={tokens.expenseBackground} weight="semibold" />
        </View>
      </PressableScale>
    </View>
  );
}
