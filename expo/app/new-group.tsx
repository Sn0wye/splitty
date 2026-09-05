import React, { useCallback, useLayoutEffect, useState } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, TextInput, View } from 'react-native';
import { Redirect, router, Stack, useNavigation } from 'expo-router';
import { api } from '@/api/client';
import { useAuth } from '@/auth/AuthContext';
import { GroupedSection } from '@/components/GroupedSection';
import { Loading } from '@/components/Screen';
import { useLastGroup } from '@/nav/LastGroupContext';
import { useTokens } from '@/theme/tokens';

export default function NewGroup(): React.JSX.Element {
  const { signedIn, loading } = useAuth();
  const { openGroup } = useLastGroup();
  const tokens = useTokens();
  const navigation = useNavigation();
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const save = useCallback(async () => {
    if (!name.trim() || busy) return;
    setBusy(true);
    setError('');
    try {
      const group = await api.createGroup(name.trim(), description.trim() || undefined);
      await openGroup(group.id, { replace: true });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Try again.');
    } finally {
      setBusy(false);
    }
  }, [busy, description, name, openGroup]);
  useLayoutEffect(() => {
    navigation.setOptions({
      title: 'New group',
      headerLeft: () => <Pressable onPress={() => router.back()}><Text style={{ fontSize: 17, color: tokens.accent }}>Cancel</Text></Pressable>,
      headerRight: () => busy
        ? <ActivityIndicator />
        : <Pressable disabled={!name.trim()} onPress={() => void save()}><Text style={{ fontSize: 17, fontWeight: '600', color: name.trim() ? tokens.accent : tokens.mutedForeground }}>Create</Text></Pressable>
    });
  }, [busy, name, navigation, save, tokens.accent, tokens.mutedForeground]);
  if (loading) return <Loading />;
  if (!signedIn) return <Redirect href="/login" />;
  return (
    <View style={{ flex: 1, backgroundColor: tokens.background }}>
      <Stack.Screen options={{ title: 'New group' }} />
      <GroupedSection>
        <TextInput accessibilityLabel="Name" autoFocus value={name} onChangeText={setName} placeholder="Name" placeholderTextColor={tokens.mutedForeground} style={{ borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: tokens.border, paddingHorizontal: 20, paddingVertical: 12, fontSize: 17, color: tokens.foreground }} />
        <TextInput accessibilityLabel="Description (optional)" value={description} onChangeText={setDescription} placeholder="Description (optional)" placeholderTextColor={tokens.mutedForeground} multiline style={{ minHeight: 44, paddingHorizontal: 20, paddingVertical: 12, fontSize: 17, color: tokens.foreground }} />
      </GroupedSection>
      {error ? <Text style={{ paddingHorizontal: 20, paddingVertical: 12, color: tokens.red }}>{error}</Text> : null}
    </View>
  );
}
