import React, { useCallback, useLayoutEffect, useState } from 'react';
import { ActivityIndicator, Alert, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { router, Stack, useFocusEffect, useLocalSearchParams, useNavigation } from 'expo-router';
import { api } from '@/api/client';
import type { Group } from '@/types';
import { GroupedRow, GroupedSection } from '@/components/GroupedSection';
import { Loading } from '@/components/Screen';
import { Avatar, ErrorMessage, PrimaryButton } from '@/components/UI';
import { useAuth } from '@/auth/AuthContext';
import { useLastGroup } from '@/nav/LastGroupContext';
import { useTokens } from '@/theme/tokens';

export default function ManageGroup(): React.JSX.Element {
  const { id } = useLocalSearchParams<{ id: string }>();
  const groupId = Number(id);
  const navigation = useNavigation();
  const { user } = useAuth();
  const tokens = useTokens();
  const { groupId: lastGroupId, setCurrentGroupId } = useLastGroup();
  const [group, setGroup] = useState<Group | null>(null);
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [formError, setFormError] = useState('');
  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const value = await api.group(groupId);
      setGroup(value);
      setName(value.name);
      setDescription(value.description ?? '');
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Could not load group.');
    } finally {
      setLoading(false);
    }
  }, [groupId]);
  useFocusEffect(useCallback(() => { void load(); }, [load]));

  const save = useCallback(async () => {
    if (!name.trim()) return;
    setBusy(true);
    setFormError('');
    try {
      await api.updateGroup(groupId, name.trim(), description.trim());
      router.back();
    } catch (caught) {
      setFormError(caught instanceof Error ? caught.message : 'Try again.');
    } finally {
      setBusy(false);
    }
  }, [description, groupId, name]);

  useLayoutEffect(() => {
    navigation.setOptions({
      title: 'Edit group',
      headerLeft: () => <Pressable onPress={() => router.back()}><Text style={{ fontSize: 17, color: tokens.accent }}>Cancel</Text></Pressable>,
      headerRight: () => busy
        ? <ActivityIndicator />
        : <Pressable disabled={!name.trim()} onPress={() => void save()}><Text style={{ fontSize: 17, fontWeight: '600', color: name.trim() ? tokens.accent : tokens.mutedForeground }}>Save</Text></Pressable>
    });
  }, [busy, name, navigation, save, tokens.accent, tokens.mutedForeground]);

  if (loading) return <Loading />;
  if (error || !group) return <View style={{ flex: 1, padding: 20, backgroundColor: tokens.background }}><ErrorMessage message={error || 'Group not found.'} onRetry={() => void load()} /></View>;

  const invite = async () => {
    try {
      const result = await api.invite(groupId);
      Alert.alert('Invite code', result.code, [{ text: 'Done' }]);
    } catch (caught) {
      Alert.alert('Could not create invite', caught instanceof Error ? caught.message : 'Try again.');
    }
  };
  const leave = () => Alert.alert('Leave group?', 'You must have a zero balance first.', [
    { text: 'Cancel', style: 'cancel' },
    { text: 'Leave', style: 'destructive', onPress: () => void api.leave(groupId).then(async () => {
      if (groupId === lastGroupId) await setCurrentGroupId(null);
      router.replace('/(tabs)');
    }).catch(caught => Alert.alert('Could not leave', caught instanceof Error ? caught.message : 'Try again.')) }
  ]);

  return (
    <ScrollView style={{ flex: 1, backgroundColor: tokens.background }}>
      <Stack.Screen options={{ title: 'Edit group' }} />
      <GroupedSection>
        <TextInput accessibilityLabel="Name" value={name} onChangeText={setName} placeholder="Name" placeholderTextColor={tokens.mutedForeground} style={{ borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: tokens.border, paddingHorizontal: 20, paddingVertical: 12, fontSize: 17, color: tokens.foreground }} />
        <TextInput accessibilityLabel="Description (optional)" value={description} onChangeText={setDescription} placeholder="Description (optional)" placeholderTextColor={tokens.mutedForeground} multiline style={{ paddingHorizontal: 20, paddingVertical: 12, fontSize: 17, color: tokens.foreground }} />
      </GroupedSection>
      {formError ? <Text style={{ paddingHorizontal: 20, paddingVertical: 12, color: tokens.red }}>{formError}</Text> : null}
      <GroupedSection header="Members">
        {group.members.map(member => (
          <GroupedRow key={member.userId}>
            <Avatar name={member.name} uri={member.avatarUrl} size={40} />
            <View style={{ marginLeft: 12, flex: 1 }}>
              <Text style={{ fontSize: 17, color: tokens.foreground }}>{member.name}</Text>
              <Text style={{ fontSize: 13, color: tokens.mutedForeground }}>{member.email}</Text>
            </View>
            {member.userId !== user?.id ? (
              <Pressable accessibilityRole="button" accessibilityLabel={`Remove ${member.name}`} onPress={() => Alert.alert(`Remove ${member.name}?`, 'They must have a zero balance.', [
                { text: 'Cancel', style: 'cancel' },
                { text: 'Remove', style: 'destructive', onPress: () => void api.removeMember(groupId, member.userId).then(() => setGroup(current => current ? { ...current, members: current.members.filter(item => item.userId !== member.userId) } : current)).catch(caught => Alert.alert('Could not remove member', caught instanceof Error ? caught.message : 'Try again.')) }
              ])}>
                <Text style={{ color: tokens.red }}>Remove</Text>
              </Pressable>
            ) : null}
          </GroupedRow>
        ))}
      </GroupedSection>
      <View style={{ marginTop: 24, gap: 12, paddingHorizontal: 20 }}>
        <PrimaryButton title="Create invite code" onPress={() => void invite()} />
        <Pressable accessibilityRole="button" onPress={leave} style={{ minHeight: 44, alignItems: 'center', justifyContent: 'center' }}>
          <Text style={{ fontWeight: '600', color: tokens.red }}>Leave group</Text>
        </Pressable>
      </View>
    </ScrollView>
  );
}
