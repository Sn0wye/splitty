import React, { useCallback, useState } from 'react';
import { Pressable, RefreshControl, ScrollView, Text, View } from 'react-native';
import { router, Stack, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { api } from '@/api/client';
import type { BalanceSummary } from '@/types';
import { Loading } from '@/components/Screen';
import { Avatar, ErrorMessage, Spinner } from '@/components/UI';
import { GroupedRow, GroupedSection } from '@/components/GroupedSection';
import { Symbol } from '@/components/Symbol';
import { overallBalanceCopy } from '@/logic/copy';
import { centsFromApi, formatCents } from '@/logic/money';
import { useAuth } from '@/auth/AuthContext';
import { useTokens } from '@/theme/tokens';

export default function Balances(): React.JSX.Element {
  const { id } = useLocalSearchParams<{ id: string }>();
  const groupId = Number(id);
  const { user } = useAuth();
  const tokens = useTokens();
  const [summary, setSummary] = useState<BalanceSummary | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const load = useCallback(async () => {
    try { setSummary(await api.balances(groupId)); setError(''); }
    catch (caught) { setError(caught instanceof Error ? caught.message : 'Could not load balances.'); }
    finally { setLoading(false); }
  }, [groupId]);
  useFocusEffect(useCallback(() => { void load(); }, [load]));
  if (loading) return <Loading label="Loading balances…" />;
  if (error) return <View style={{ flex: 1, padding: 20, backgroundColor: tokens.background }}><ErrorMessage message={error} onRetry={() => void load()} /></View>;
  const rows = (summary?.balances ?? []).filter(row => row.userId === user?.id && centsFromApi(row.amount) !== 0);
  const net = rows.reduce((sum, row) => sum + centsFromApi(row.amount), 0);
  const max = Math.max(1, ...rows.map(row => Math.abs(centsFromApi(row.amount))));
  return (
    <View style={{ flex: 1, backgroundColor: tokens.background }}>
      <Stack.Screen options={{
        title: 'Balances',
        headerRight: () => (
          <Pressable accessibilityRole="button" onPress={() => router.back()}><Text style={{ fontSize: 17, color: tokens.accent }}>Done</Text></Pressable>
        )
      }} />
      <ScrollView refreshControl={<RefreshControl tintColor={tokens.mutedForeground} refreshing={refreshing} onRefresh={() => { setRefreshing(true); void load().finally(() => setRefreshing(false)); }} />}>
        <View style={{ paddingHorizontal: 20, paddingVertical: 20 }}>
          <Text style={{ fontSize: 15, fontWeight: '500', color: tokens.mutedForeground }}>Your balance</Text>
          <View style={{ marginTop: 8, flexDirection: 'row', alignItems: 'center' }}>
            <Text style={{ fontSize: 22, fontWeight: '700', color: tokens.foreground, fontVariant: ['tabular-nums'], opacity: summary?.balancesPending ? 0.5 : 1 }}>
              {overallBalanceCopy(net)}
            </Text>
            {summary?.balancesPending ? <View style={{ marginLeft: 10 }}><Spinner /></View> : null}
          </View>
        </View>
        <GroupedSection header="Open balances">
          {rows.length === 0 ? (
            <GroupedRow>
              <Symbol sf="checkmark.circle.fill" ion="checkmark-circle" size={17} color={tokens.mutedForeground} />
              <Text style={{ marginLeft: 8, fontSize: 17, color: tokens.mutedForeground }}>Everyone is settled up</Text>
            </GroupedRow>
          ) : rows.map(row => {
            const amount = centsFromApi(row.amount);
            const youOwe = amount < 0;
            const fraction = Math.abs(amount) / max;
            const color = youOwe ? tokens.red : tokens.green;
            return (
              <View key={row.id} style={{ overflow: 'hidden' }}>
                <View style={{ position: 'absolute', top: 4, bottom: 4, left: 0, width: `${Math.round(fraction * 100)}%`, backgroundColor: `${color}24`, borderRadius: 10 }} />
                <GroupedRow paddingHorizontal={16}>
                  <Avatar name={row.peer.name} uri={row.peer.avatarUrl} size={40} />
                  <Text style={{ marginLeft: 12, flex: 1, fontSize: 17, fontWeight: '600', color: tokens.cardForeground }}>
                    {youOwe ? `You owe ${row.peer.name}` : `${row.peer.name} owes you`}
                  </Text>
                  <Text style={{ fontSize: 17, fontWeight: '600', color, fontVariant: ['tabular-nums'], opacity: summary?.balancesPending ? 0.5 : 1 }}>
                    {formatCents(Math.abs(amount))}
                  </Text>
                </GroupedRow>
              </View>
            );
          })}
        </GroupedSection>
      </ScrollView>
    </View>
  );
}
