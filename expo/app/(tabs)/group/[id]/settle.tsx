import React, { useCallback, useState } from 'react';
import { Alert, Pressable, Text, View } from 'react-native';
import { router, Stack, useFocusEffect, useLocalSearchParams } from 'expo-router';
import { api } from '@/api/client';
import type { Balance, Group } from '@/types';
import { Loading } from '@/components/Screen';
import { ErrorMessage, Field, PrimaryButton } from '@/components/UI';
import { centsFromApi, formatCents, parseTypedMoney } from '@/logic/money';
import { useAuth } from '@/auth/AuthContext';

export default function Settle(): React.JSX.Element {
  const { id } = useLocalSearchParams<{ id: string }>();
  const groupId = Number(id);
  const { user } = useAuth();
  const [group, setGroup] = useState<Group | null>(null);
  const [rows, setRows] = useState<Balance[]>([]);
  const [peer, setPeer] = useState<Balance | null>(null);
  const [amount, setAmount] = useState('');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const [nextGroup, summary] = await Promise.all([api.group(groupId), api.balances(groupId)]);
      const owing = summary.balances.filter(row => row.userId === user?.id && centsFromApi(row.amount) < 0);
      setGroup(nextGroup);
      setRows(owing);
      setPeer(current => current && owing.some(row => row.id === current.id) ? current : owing[0] ?? null);
      setAmount(owing[0] ? (Math.abs(centsFromApi(owing[0].amount)) / 100).toFixed(2) : '');
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Could not load balances.');
    } finally {
      setLoading(false);
    }
  }, [groupId, user]);
  useFocusEffect(useCallback(() => { void load(); }, [load]));
  if (loading) return <Loading />;
  if (error || !group) return <View className="flex-1 bg-background p-5 dark:bg-background-dark"><ErrorMessage message={error || 'Group not found.'} onRetry={() => void load()} /></View>;
  const save = async () => {
    const amountCents = parseTypedMoney(amount);
    if (!peer || amountCents === null || amountCents <= 0) return;
    setBusy(true);
    try {
      await api.settle(groupId, peer.peerId, amountCents);
      router.back();
    } catch (caught) {
      Alert.alert('Could not settle up', caught instanceof Error ? caught.message : 'The amount may exceed what you owe.');
    } finally {
      setBusy(false);
    }
  };
  return (
    <View className="flex-1 bg-background dark:bg-background-dark">
      <Stack.Screen options={{
        title: 'Settle up',
        headerLeft: () => <Pressable onPress={() => router.back()}><Text className="text-[17px] text-accent">Cancel</Text></Pressable>
      }} />
      <View className="px-5 py-4">
        <Text className="mb-4 text-[13px] text-muted-foreground dark:text-muted-foreground-dark">Record a payment from you to a member you owe. Settlements are capped at your current balance.</Text>
        {rows.map(row => (
          <Pressable
            key={row.id}
            onPress={() => { setPeer(row); setAmount((Math.abs(centsFromApi(row.amount)) / 100).toFixed(2)); }}
            className="min-h-11 flex-row items-center border-b border-border py-3 dark:border-border-dark"
          >
            <Text className="flex-1 text-[17px] text-foreground dark:text-foreground-dark">You owe {row.peer.name}</Text>
            <Text className={`text-[17px] ${peer?.id === row.id ? 'font-semibold text-foreground dark:text-foreground-dark' : 'text-muted-foreground dark:text-muted-foreground-dark'}`}>
              {formatCents(Math.abs(centsFromApi(row.amount)))}
            </Text>
          </Pressable>
        ))}
        {peer ? (
          <View className="mt-6">
            <Field label={`Amount paid to ${peer.peer.name}`} value={amount} onChangeText={setAmount} keyboardType="decimal-pad" />
            <PrimaryButton title="Record settlement" isLoading={busy} disabled={busy || (parseTypedMoney(amount) ?? 0) <= 0} onPress={() => void save()} />
          </View>
        ) : <Text className="py-10 text-center text-muted-foreground dark:text-muted-foreground-dark">You have no outstanding balances.</Text>}
      </View>
    </View>
  );
}
