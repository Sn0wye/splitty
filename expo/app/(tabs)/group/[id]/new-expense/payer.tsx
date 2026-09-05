import React from 'react';
import { Pressable, ScrollView, Text } from 'react-native';
import { router, Stack } from 'expo-router';
import { GroupedRow, GroupedSection } from '@/components/GroupedSection';
import { Symbol } from '@/components/Symbol';
import { useExpenseForm } from '@/expense/ExpenseFormContext';
import { useTokens } from '@/theme/tokens';

export default function ExpensePayer(): React.JSX.Element {
  const tokens = useTokens();
  const form = useExpenseForm();
  return (
    <ScrollView style={{ flex: 1, backgroundColor: tokens.background }}>
      <Stack.Screen options={{ title: 'Paid by' }} />
      <GroupedSection>
        {form.group.members.map(member => (
          <Pressable
            key={member.userId}
            testID={`split.payer.${member.userId}`}
            onPress={() => { form.setPaidBy(member.userId); router.back(); }}
          >
            <GroupedRow>
              <Text style={{ flex: 1, fontSize: 17, color: tokens.foreground }}>{form.you(member.userId, member.name)}</Text>
              {form.paidBy === member.userId ? <Symbol sf="checkmark" ion="checkmark" size={18} color={tokens.accent} /> : null}
            </GroupedRow>
          </Pressable>
        ))}
      </GroupedSection>
    </ScrollView>
  );
}
