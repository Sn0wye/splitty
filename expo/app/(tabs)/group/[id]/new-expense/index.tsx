import React from 'react';
import { Pressable, Text, View } from 'react-native';
import { router, Stack } from 'expo-router';
import { AmountDisplay } from '@/components/AmountDisplay';
import { ExpenseKeypad } from '@/components/ExpenseKeypad';
import { PrimaryButton } from '@/components/UI';
import { useExpenseForm } from '@/expense/ExpenseFormContext';
import { useTokens } from '@/theme/tokens';

export default function ExpenseAmount(): React.JSX.Element {
  const tokens = useTokens();
  const form = useExpenseForm();
  return (
    <View style={{ flex: 1, backgroundColor: tokens.expenseBackground }}>
      <Stack.Screen options={{
        title: '',
        headerLeft: () => (
          <Pressable accessibilityRole="button" accessibilityLabel="Cancel" testID="expense.cancel" onPress={() => router.back()}>
            <Text style={{ color: tokens.expenseForeground, fontSize: 17 }}>Cancel</Text>
          </Pressable>
        )
      }} />
      <View style={{ flex: 1, justifyContent: 'center' }}>
        <AmountDisplay text={form.display} />
      </View>
      <View style={{ paddingHorizontal: 20, paddingBottom: 16 }}>
        <PrimaryButton title="Next" testID="expense.next" disabled={form.totalCents === 0} onPress={() => router.push(`/group/${form.group.id}/new-expense/details`)} />
      </View>
      <ExpenseKeypad onKey={form.pressKey} />
    </View>
  );
}
