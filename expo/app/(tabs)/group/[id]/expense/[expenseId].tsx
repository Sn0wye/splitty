import React, { useCallback, useState } from 'react';
import { ActivityIndicator, Pressable, Text, View } from 'react-native';
import { router, Stack, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { api } from '@/api/client';
import type { Expense } from '@/types';
import { presentConfirmationDialog } from '@/components/confirm';
import { GroupedRow, GroupedSection } from '@/components/GroupedSection';
import { Loading } from '@/components/Screen';
import { ErrorMessage } from '@/components/UI';
import { Symbol } from '@/components/Symbol';
import { detailDateText } from '@/logic/copy';
import { centsFromApi, formatCents } from '@/logic/money';
import { memberDisplayName } from '@/logic/memberName';
import { useAuth } from '@/auth/AuthContext';
import { useTokens } from '@/theme/tokens';

export default function ExpenseDetail(): React.JSX.Element {
  const { id, expenseId } = useLocalSearchParams<{ id: string; expenseId: string }>();
  const groupId = Number(id);
  const itemId = Number(expenseId);
  const { user } = useAuth();
  const tokens = useTokens();
  const [expense, setExpense] = useState<Expense | null>(null);
  const [error, setError] = useState('');
  const [deleting, setDeleting] = useState(false);
  const load = useCallback(async () => {
    try { setExpense(await api.expense(groupId, itemId)); setError(''); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Could not load expense.'); }
  }, [groupId, itemId]);
  useFocusEffect(useCallback(() => { void load(); }, [load]));
  if (!expense && !error) return <Loading />;
  if (error || !expense) return <View style={{ flex: 1, padding: 20, backgroundColor: tokens.background }}><ErrorMessage message={error || 'Expense not found.'} onRetry={() => void load()} /></View>;
  const isPayment = expense.type === 'payment';
  const peer = expense.splits.find(split => split.userId !== expense.paidBy)?.user;
  const payerName = expense.paidBy === user?.id ? 'You' : expense.paidByUser.name;
  const payeeName = peer ? (peer.id === user?.id ? 'you' : peer.name) : 'someone who has left';
  const date = new Date(expense.date ?? expense.createdAt);
  const splitHeader = expense.splitMode === 'percentage' ? 'Split by percentages' : expense.splitMode === 'custom' ? 'Split by amounts' : expense.splitMode === 'equal' ? 'Split equally' : 'Split';
  const remove = () => {
    const title = isPayment
      ? `Delete the ${formatCents(centsFromApi(expense.amount))} payment from ${payerName} to ${payeeName}?`
      : `Delete "${expense.description}"?`;
    const message = isPayment
      ? 'The balance between them goes back to what it was before this payment.'
      : "This removes the expense and everyone's share of it.";
    presentConfirmationDialog({
      title,
      message,
      onConfirm: () => {
        setDeleting(true);
        void (isPayment ? api.deleteSettlement(groupId, itemId) : api.deleteExpense(groupId, itemId))
          .then(() => router.back())
          .catch(caught => { setError(caught instanceof Error ? caught.message : 'Try again.'); setDeleting(false); });
      }
    });
  };
  const nameFor = (userId: number, name: string) => memberDisplayName(userId, name, user?.id);
  return (
    <View style={{ flex: 1, backgroundColor: tokens.background }}>
      <Stack.Screen options={{
        title: isPayment ? 'Settlement' : 'Expense',
        headerRight: () => (
          <View style={{ flexDirection: 'row', alignItems: 'center' }}>
            {deleting ? <ActivityIndicator /> : (
              <Pressable accessibilityRole="button" accessibilityLabel={isPayment ? 'Delete settlement' : 'Delete expense'} onPress={remove} style={{ paddingHorizontal: 8 }}>
                <Symbol sf="trash" ion="trash" size={20} color={tokens.foreground} />
              </Pressable>
            )}
            {!isPayment ? (
              <Pressable disabled={deleting} onPress={() => router.push(`/group/${groupId}/new-expense?expenseId=${itemId}`)} style={{ paddingHorizontal: 8 }}>
                <Text style={{ fontSize: 17, color: tokens.accent }}>Edit</Text>
              </Pressable>
            ) : null}
          </View>
        )
      }} />
      <GroupedSection>
        <View style={{ paddingHorizontal: 20, paddingVertical: 16 }}>
          {isPayment ? (
            <>
              <Text style={{ fontSize: 34, fontWeight: '700', color: tokens.foreground, fontVariant: ['tabular-nums'] }}>{formatCents(centsFromApi(expense.amount))}</Text>
              <Text style={{ marginTop: 6, fontSize: 17, fontWeight: '600', color: tokens.foreground }}>{payerName} paid {payeeName}</Text>
              <Text style={{ marginTop: 6, fontSize: 15, color: tokens.mutedForeground }}>{Number.isNaN(date.getTime()) ? 'Unknown date' : detailDateText(date)}</Text>
            </>
          ) : (
            <>
              <Text style={{ fontSize: 22, fontWeight: '600', color: tokens.foreground }}>{expense.description}</Text>
              <Text style={{ marginTop: 6, fontSize: 34, fontWeight: '700', color: tokens.foreground, fontVariant: ['tabular-nums'] }}>{formatCents(centsFromApi(expense.amount))}</Text>
              <Text style={{ marginTop: 6, fontSize: 15, color: tokens.mutedForeground }}>
                {payerName} paid · {Number.isNaN(date.getTime()) ? 'Unknown date' : detailDateText(date)}
              </Text>
            </>
          )}
        </View>
      </GroupedSection>
      {!isPayment ? (
        <GroupedSection header={splitHeader}>
          {expense.splits.map(split => (
            <GroupedRow key={split.id}>
              <Text style={{ flex: 1, fontSize: 17, color: tokens.foreground }}>{nameFor(split.userId, split.user.name)}</Text>
              {expense.splitMode === 'percentage' && split.percentage != null ? (
                <Text style={{ marginRight: 12, fontSize: 15, fontVariant: ['tabular-nums'], color: tokens.mutedForeground }}>{split.percentage}%</Text>
              ) : null}
              <Text style={{ fontSize: 17, fontVariant: ['tabular-nums'], color: tokens.mutedForeground }}>{formatCents(centsFromApi(split.amount))}</Text>
            </GroupedRow>
          ))}
        </GroupedSection>
      ) : (
        <Text style={{ paddingHorizontal: 20, paddingVertical: 16, fontSize: 13, color: tokens.mutedForeground }}>
          Any member can delete a settlement, including one someone else recorded.
        </Text>
      )}
      {error ? <Text style={{ paddingHorizontal: 20, paddingVertical: 12, color: tokens.red }}>{error}</Text> : null}
    </View>
  );
}
