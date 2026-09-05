import React, { useCallback, useLayoutEffect, useState } from 'react';
import { ActivityIndicator, Pressable, Text, TextInput, View } from 'react-native';
import { Redirect, router, Stack, useNavigation } from 'expo-router';
import { api } from '@/api/client';
import { useAuth } from '@/auth/AuthContext';
import { GroupedSection } from '@/components/GroupedSection';
import { Loading } from '@/components/Screen';
import { useLastGroup } from '@/nav/LastGroupContext';
import { systemMonospacedTitle2 } from '@/theme/fonts';
import { useTokens } from '@/theme/tokens';

const normalizeCode = (value: string): string => value.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 6);

export default function Join(): React.JSX.Element {
  const { signedIn, loading } = useAuth();
  const { openGroup } = useLastGroup();
  const tokens = useTokens();
  const navigation = useNavigation();
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const submit = useCallback(async () => {
    if (code.length !== 6 || busy) return;
    setBusy(true);
    setError('');
    try {
      const group = await api.acceptInvite(code);
      await openGroup(group.id, { replace: true });
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Check the invite code.');
    } finally {
      setBusy(false);
    }
  }, [busy, code, openGroup]);
  useLayoutEffect(() => {
    navigation.setOptions({
      title: 'Join with code',
      headerLeft: () => <Pressable onPress={() => router.back()}><Text style={{ fontSize: 17, color: tokens.accent }}>Cancel</Text></Pressable>,
      headerRight: () => busy
        ? <ActivityIndicator />
        : <Pressable disabled={code.length !== 6} onPress={() => void submit()}><Text style={{ fontSize: 17, fontWeight: '600', color: code.length === 6 ? tokens.accent : tokens.mutedForeground }}>Join</Text></Pressable>
    });
  }, [busy, code, navigation, submit, tokens.accent, tokens.mutedForeground]);
  if (loading) return <Loading />;
  if (!signedIn) return <Redirect href="/login" />;
  return (
    <View style={{ flex: 1, backgroundColor: tokens.background }}>
      <Stack.Screen options={{ title: 'Join with code' }} />
      <GroupedSection footer="Ask a group member for their 6-character invite code.">
        <TextInput
          accessibilityLabel="Invite code"
          autoFocus
          autoCapitalize="characters"
          autoCorrect={false}
          value={code}
          onChangeText={value => setCode(normalizeCode(value))}
          placeholder="Invite code"
          placeholderTextColor={tokens.mutedForeground}
          style={[{ paddingHorizontal: 20, paddingVertical: 12, color: tokens.foreground, textAlign: 'left' }, systemMonospacedTitle2()]}
        />
      </GroupedSection>
      {error ? <Text style={{ paddingHorizontal: 20, paddingVertical: 12, color: tokens.red }}>{error}</Text> : null}
    </View>
  );
}
