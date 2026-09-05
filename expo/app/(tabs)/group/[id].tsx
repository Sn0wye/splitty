import React, { useCallback, useState } from 'react';
import { Alert, NativeScrollEvent, NativeSyntheticEvent, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { router, useFocusEffect, useLocalSearchParams } from 'expo-router';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';
import { api } from '@/api/client';
import type { Expense, Group } from '@/types';
import { Loading } from '@/components/Screen';
import { ActionButton, ErrorMessage, MultipleAvatar, Spinner } from '@/components/UI';
import { ExpenseRow } from '@/components/ExpenseRow';
import { PressableScale } from '@/components/PressableScale';
import { SwipeToDeleteRow } from '@/components/SwipeToDeleteRow';
import { Symbol } from '@/components/Symbol';
import { useReducedMotion } from '@/hooks/useReducedMotion';
import { overallBalanceCopy } from '@/logic/copy';
import { centsFromApi, formatCents } from '@/logic/money';
import { groupExpensesByDay } from '@/logic/timeline';
import { useAuth } from '@/auth/AuthContext';
import { useLastGroup } from '@/nav/LastGroupContext';
import { useTokens } from '@/theme/tokens';

export default function GroupScreen(): React.JSX.Element {
  const { id } = useLocalSearchParams<{ id: string }>();
  const groupId = Number(id);
  const { user } = useAuth();
  const { setCurrentGroupId } = useLastGroup();
  const tokens = useTokens();
  const insets = useSafeAreaInsets();
  const reduced = useReducedMotion();
  const [group, setGroup] = useState<Group | null>(null);
  const [expenses, setExpenses] = useState<Expense[]>([]);
  const [pending, setPending] = useState(false);
  const [balancesPending, setBalancesPending] = useState(false);
  const [error, setError] = useState('');
  const [actionError, setActionError] = useState('');
  const [collapsed, setCollapsed] = useState(false);
  const titleOpacity = useSharedValue(0);

  const load = useCallback(async () => {
    try {
      const [nextGroup, nextExpenses] = await Promise.all([api.group(groupId), api.expenses(groupId)]);
      setGroup(nextGroup);
      setExpenses(nextExpenses);
      setError('');
      try { setBalancesPending((await api.balances(groupId)).balancesPending); } catch { setBalancesPending(false); }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Could not load this group.');
    } finally {
      setPending(false);
    }
  }, [groupId]);

  useFocusEffect(useCallback(() => {
    if (Number.isInteger(groupId)) void setCurrentGroupId(groupId);
    void load();
  }, [groupId, load, setCurrentGroupId]));

  const onScroll = (event: NativeSyntheticEvent<NativeScrollEvent>) => {
    const next = event.nativeEvent.contentOffset.y > 52;
    if (next === collapsed) return;
    setCollapsed(next);
    titleOpacity.value = withTiming(next ? 1 : 0, {
      duration: reduced ? 0 : 200,
      easing: Easing.inOut(Easing.ease)
    });
  };

  const titleStyle = useAnimatedStyle(() => ({ opacity: titleOpacity.value }));

  const remove = (expense: Expense) => {
    const title = expense.type === 'payment'
      ? `Delete the ${formatCents(centsFromApi(expense.amount))} payment?`
      : `Delete "${expense.description}"?`;
    Alert.alert(title, 'This cannot be undone.', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: () => {
          void (expense.type === 'payment' ? api.deleteSettlement(groupId, expense.id) : api.deleteExpense(groupId, expense.id))
            .then(load)
            .catch(caught => setActionError(caught instanceof Error ? caught.message : 'Try again.'));
        }
      }
    ]);
  };

  if (!group && !error) return <Loading label="Loading..." />;
  if (error && !group) {
    return (
      <View style={{ flex: 1, paddingHorizontal: 20, backgroundColor: tokens.background }}>
        <ErrorMessage message={error} onRetry={() => void load()} />
      </View>
    );
  }

  const net = group ? centsFromApi(group.netBalance) : 0;
  const days = groupExpensesByDay(expenses);

  return (
    <View style={{ flex: 1, backgroundColor: tokens.background }}>
      <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 8, paddingBottom: 8, paddingTop: insets.top }}>
        <Pressable accessibilityRole="button" accessibilityLabel="Back to groups" onPress={() => router.navigate('/(tabs)')} style={styles.barButton}>
          <Symbol sf="chevron.left" ion="chevron-back" size={17} color={tokens.foreground} weight="semibold" />
        </Pressable>
        <Animated.Text style={[{ flex: 1, textAlign: 'center', fontSize: 17, fontWeight: '600', color: tokens.foreground }, titleStyle]}>
          {group?.name ?? ''}
        </Animated.Text>
        <Pressable accessibilityRole="button" accessibilityLabel="Edit group" disabled={!group} onPress={() => router.push(`/group/${groupId}/manage`)} style={styles.barButton}>
          <Symbol sf="gearshape" ion="settings-outline" size={17} color={tokens.foreground} />
        </Pressable>
      </View>
      <ScrollView
        style={{ flex: 1 }}
        onScroll={onScroll}
        scrollEventThrottle={16}
        refreshControl={<RefreshControl refreshing={pending} onRefresh={() => { setPending(true); void load(); }} />}
        contentContainerStyle={{ paddingBottom: 112 }}
      >
        <View style={{ flexDirection: 'row', alignItems: 'center', paddingHorizontal: 20, paddingTop: 10 }}>
          <MultipleAvatar members={group?.members ?? []} />
          <View style={{ marginLeft: 16, flex: 1 }}>
            <Text style={{ fontSize: 34, fontWeight: '700', color: tokens.foreground }}>{group?.name ?? 'Loading...'}</Text>
            <View style={{ marginTop: 4, flexDirection: 'row', alignItems: 'center' }}>
              <Text style={{ color: tokens.mutedForeground, opacity: balancesPending ? 0.5 : 1 }}>
                {group ? overallBalanceCopy(net) : 'Loading balance...'}
              </Text>
              {balancesPending ? <View style={{ marginLeft: 6 }}><Spinner /></View> : null}
            </View>
          </View>
        </View>
        <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: 12, paddingHorizontal: 20, paddingVertical: 20 }}>
          <ActionButton title="Settle up" filled onPress={() => router.push(`/group/${groupId}/settle`)} />
          <ActionButton title="Charts" onPress={() => undefined} />
          <ActionButton title="Balances" disabled={!group || !user} onPress={() => router.push(`/group/${groupId}/balances`)} />
          <ActionButton title="Export" onPress={() => undefined} />
        </ScrollView>
        {actionError ? <Text style={{ backgroundColor: tokens.card, paddingHorizontal: 20, paddingVertical: 12, color: tokens.red }}>{actionError}</Text> : null}
        {error ? <Text style={{ backgroundColor: tokens.card, paddingHorizontal: 20, paddingVertical: 12, color: tokens.red }}>Error: {error}</Text> : null}
        {!error && expenses.length === 0 ? (
          <Text style={{ backgroundColor: tokens.card, paddingHorizontal: 20, paddingVertical: 16, color: tokens.mutedForeground }}>No expenses yet. Add the first one.</Text>
        ) : days.map(day => (
          <View key={day.key}>
            <View style={{ flexDirection: 'row', alignItems: 'center', backgroundColor: tokens.card, paddingHorizontal: 20, paddingVertical: 16 }}>
              <Text style={{ flex: 1, fontSize: 22, fontWeight: '600', color: tokens.cardForeground }}>{day.label}</Text>
              <Text style={{ fontSize: 15, color: tokens.mutedForeground }}>Latest</Text>
              <View style={{ marginLeft: 8 }}>
                <Symbol sf="chevron.down" ion="chevron-down" size={12} color={tokens.mutedForeground} />
              </View>
            </View>
            {day.expenses.map(expense => (
              <View key={expense.id} style={{ borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: tokens.border }}>
                {user ? (
                  <SwipeToDeleteRow
                    accessibilityLabel={`Open ${expense.description}`}
                    onPress={() => router.push(`/group/${groupId}/expense/${expense.id}`)}
                    onDelete={() => remove(expense)}
                  >
                    <ExpenseRow expense={expense} currentUserId={user.id} />
                  </SwipeToDeleteRow>
                ) : null}
              </View>
            ))}
          </View>
        ))}
      </ScrollView>
      <PressableScale
        accessibilityRole="button"
        accessibilityLabel="Add expense"
        testID="group.addExpense"
        disabled={!user || !group}
        scale={0.9}
        onPress={() => router.push(`/group/${groupId}/new-expense`)}
        style={{ position: 'absolute', bottom: 16, right: 20 }}
      >
        <View style={{ height: 56, width: 56, alignItems: 'center', justifyContent: 'center', borderRadius: 28, backgroundColor: tokens.foreground, shadowColor: '#000', shadowOffset: { width: 0, height: 4 }, shadowRadius: 8, shadowOpacity: 0.25, elevation: 6 }}>
          <Symbol sf="plus" ion="add" size={22} color={tokens.background} weight="semibold" />
        </View>
      </PressableScale>
    </View>
  );
}

const styles = StyleSheet.create({
  barButton: { height: 44, width: 44, alignItems: 'center', justifyContent: 'center' }
});
