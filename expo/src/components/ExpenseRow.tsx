import React from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { Symbol } from '@/components/Symbol';
import { centsFromApi, formatCents } from '@/logic/money';
import { userSplitCents } from '@/logic/split';
import { useTokens } from '@/theme/tokens';
import type { Expense } from '@/types';

export function ExpenseRow({ expense, currentUserId }: { expense: Expense; currentUserId: number }): React.JSX.Element {
  const tokens = useTokens();
  const isPayment = expense.type === 'payment';
  const isUserPaid = expense.paidBy === currentUserId;
  const peer = expense.splits.find(split => split.userId !== expense.paidBy)?.user;
  const peerName = peer?.name ?? 'someone';
  const payeeLabel = peer?.id === currentUserId ? 'you' : peerName;
  const impact = userSplitCents(expense, currentUserId);
  const moneyColor = isPayment ? tokens.cardForeground : isUserPaid ? tokens.green : tokens.red;
  return (
    <View style={styles.row}>
      <View style={[styles.icon, { backgroundColor: isPayment ? tokens.green : tokens.blue }]}>
        {isPayment
          ? <Symbol sf="arrow.left.arrow.right" ion="swap-horizontal" size={18} color="#FFFFFF" />
          : <Symbol sf="dollarsign.circle.fill" ion="logo-usd" size={18} color="#FFFFFF" />}
      </View>
      <View style={styles.main}>
        <Text style={[styles.title, { color: tokens.cardForeground }]}>{expense.description}</Text>
        <Text style={[styles.sub, { color: tokens.mutedForeground }]}>
          {isPayment
            ? (isUserPaid ? `You paid ${peerName}` : `${expense.paidByUser.name} paid ${payeeLabel}`)
            : (isUserPaid ? `You paid ${formatCents(centsFromApi(expense.amount))}` : `${expense.paidByUser.name} paid ${formatCents(centsFromApi(expense.amount))}`)}
        </Text>
      </View>
      <View style={styles.trail}>
        {isPayment
          ? <Text style={[styles.caption, { color: tokens.mutedForeground }]}>payment</Text>
          : <Text style={[styles.caption, { color: isUserPaid ? tokens.green : tokens.red }]}>{isUserPaid ? 'you lent' : 'you borrowed'}</Text>}
        <Text style={[styles.amount, { color: moneyColor }]}>
          {isPayment ? formatCents(centsFromApi(expense.amount)) : formatCents(Math.abs(impact))}
        </Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  row: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 20, paddingVertical: 16 },
  icon: { marginRight: 16, height: 40, width: 40, alignItems: 'center', justifyContent: 'center', borderRadius: 20 },
  main: { flex: 1, gap: 4 },
  title: { fontSize: 17, fontWeight: '600' },
  sub: { fontSize: 15 },
  trail: { alignItems: 'flex-end', gap: 4 },
  caption: { fontSize: 12 },
  amount: { fontSize: 17, fontWeight: '600' }
});
