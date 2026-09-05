import React from 'react';
import { Pressable, ScrollView, Text, TextInput, View } from 'react-native';
import SegmentedControl from '@react-native-segmented-control/segmented-control';
import { router, Stack } from 'expo-router';
import { GroupedRow, GroupedSection } from '@/components/GroupedSection';
import { Symbol } from '@/components/Symbol';
import { useExpenseForm } from '@/expense/ExpenseFormContext';
import { formatCents } from '@/logic/money';
import { useTokens } from '@/theme/tokens';
import type { SplitMode } from '@/types';

const modes = ['equal', 'custom', 'percentage'] as const satisfies readonly SplitMode[];

export default function ExpenseSplit(): React.JSX.Element {
  const tokens = useTokens();
  const form = useExpenseForm();
  const payerName = form.you(form.paidBy, form.group.members.find(member => member.userId === form.paidBy)?.name ?? '');
  const header = form.mode === 'equal' ? 'Split between' : form.mode === 'custom' ? 'Amounts' : 'Percentages';
  const footer = form.blocking ?? (form.mode === 'equal' ? undefined : 'Everything is assigned. A blank field is someone left out.');
  return (
    <ScrollView style={{ flex: 1, backgroundColor: tokens.background }} keyboardShouldPersistTaps="handled">
      <Stack.Screen options={{
        title: 'Split',
        headerRight: () => (
          <Pressable onPress={() => router.back()}><Text style={{ fontSize: 17, color: tokens.accent }}>Done</Text></Pressable>
        )
      }} />
      <GroupedSection>
        <Pressable accessibilityRole="button" testID="split.payer" onPress={() => router.push(`/group/${form.group.id}/new-expense/payer`)}>
          <GroupedRow>
            <Text style={{ flex: 1, fontSize: 17, color: tokens.foreground }}>Paid by</Text>
            <Text style={{ color: tokens.mutedForeground }}>{payerName}</Text>
            <Symbol sf="chevron.right" ion="chevron-forward" size={14} color={tokens.mutedForeground} />
          </GroupedRow>
        </Pressable>
      </GroupedSection>
      <View style={{ marginHorizontal: 20, marginTop: 16 }}>
        <SegmentedControl
          values={['Equally', 'Amounts', 'Percentages']}
          selectedIndex={Math.max(0, modes.indexOf(form.mode))}
          onChange={event => {
            const next = modes[event.nativeEvent.selectedSegmentIndex];
            if (next) form.setMode(next);
          }}
          testID="split.mode"
          accessibilityLabel="Split"
        />
      </View>
      <GroupedSection header={header} footer={footer} footerColor={form.blocking ? '#FF9500' : undefined}>
        {form.group.members.map(member => {
          const selected = form.participants.includes(member.userId);
          const share = form.preview[member.userId] ?? 0;
          if (form.mode === 'equal') {
            return (
              <Pressable
                key={member.userId}
                testID={`split.member.${member.userId}`}
                onPress={() => form.setParticipants(current => current.includes(member.userId) ? current.filter(idValue => idValue !== member.userId) : [...current, member.userId])}
              >
                <GroupedRow>
                  <Symbol
                    sf={selected ? 'checkmark.circle.fill' : 'circle'}
                    ion={selected ? 'checkmark-circle' : 'ellipse-outline'}
                    size={22}
                    color={selected ? tokens.accent : tokens.mutedForeground}
                  />
                  <Text style={{ marginLeft: 12, flex: 1, fontSize: 17, color: tokens.foreground }}>{form.you(member.userId, member.name)}</Text>
                  <Text style={{ fontVariant: ['tabular-nums'], color: tokens.mutedForeground }}>{formatCents(share)}</Text>
                </GroupedRow>
              </Pressable>
            );
          }
          if (form.mode === 'custom') {
            return (
              <GroupedRow key={member.userId}>
                <Text style={{ flex: 1, fontSize: 17, color: tokens.foreground }}>{form.you(member.userId, member.name)}</Text>
                <Text style={{ color: tokens.mutedForeground }}>$</Text>
                <TextInput
                  accessibilityLabel={`${member.name} amount`}
                  testID={`split.amount.${member.userId}`}
                  value={form.custom[member.userId] ?? ''}
                  onChangeText={value => form.setCustom(current => ({ ...current, [member.userId]: value }))}
                  keyboardType="decimal-pad"
                  placeholder="0"
                  style={{ width: 90, textAlign: 'right', fontSize: 17, fontVariant: ['tabular-nums'], color: tokens.foreground }}
                />
              </GroupedRow>
            );
          }
          return (
            <GroupedRow key={member.userId}>
              <Text style={{ flex: 1, fontSize: 17, color: tokens.foreground }}>{form.you(member.userId, member.name)}</Text>
              <Text style={{ marginRight: 8, fontVariant: ['tabular-nums'], color: tokens.mutedForeground }}>{formatCents(share)}</Text>
              <TextInput
                accessibilityLabel={`${member.name} percentage`}
                testID={`split.percentage.${member.userId}`}
                value={form.percentages[member.userId] ?? ''}
                onChangeText={value => form.setPercentages(current => ({ ...current, [member.userId]: value }))}
                keyboardType="decimal-pad"
                placeholder="0"
                style={{ width: 60, textAlign: 'right', fontSize: 17, fontVariant: ['tabular-nums'], color: tokens.foreground }}
              />
              <Text style={{ color: tokens.mutedForeground }}>%</Text>
            </GroupedRow>
          );
        })}
      </GroupedSection>
    </ScrollView>
  );
}
