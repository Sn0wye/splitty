import React, { useCallback, useState } from 'react';
import { RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { router, useFocusEffect } from 'expo-router';
import { api } from '@/api/client';
import type { Group } from '@/types';
import { Screen, Loading } from '@/components/Screen';
import { AnchorMenu } from '@/components/AnchorMenu';
import { CurrentUserAvatar, ErrorMessage } from '@/components/UI';
import { GroupCard } from '@/components/GroupCard';
import { Symbol } from '@/components/Symbol';
import { overallBalanceCents, overallBalanceCopy } from '@/logic/copy';
import { useAuth } from '@/auth/AuthContext';
import { useLastGroup } from '@/nav/LastGroupContext';
import { useTokens } from '@/theme/tokens';

export default function Groups(): React.JSX.Element {
  const { user } = useAuth();
  const { openGroup } = useLastGroup();
  const tokens = useTokens();
  const [groups, setGroups] = useState<Group[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [error, setError] = useState('');
  const load = useCallback(async (refresh = false) => {
    if (refresh) setRefreshing(true);
    else setLoading(true);
    try {
      setGroups(await api.groups());
      setError('');
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Could not load groups.');
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, []);
  useFocusEffect(useCallback(() => { void load(); }, [load]));

  if (loading) return <Loading label="Loading..." />;
  const overall = overallBalanceCents(groups);
  return (
    <Screen edges={['top']}>
      <View style={styles.header}>
        <View style={{ flex: 1 }}>
          <Text style={{ fontSize: 34, fontWeight: '700', color: tokens.foreground }}>Groups</Text>
          {overall != null ? <Text style={{ color: tokens.mutedForeground }}>{overallBalanceCopy(overall)}</Text> : null}
        </View>
        <AnchorMenu
          accessibilityLabel="Add"
          actions={[
            { id: 'new', title: 'New group' },
            { id: 'join', title: 'Join with code' }
          ]}
          onAction={id => {
            if (id === 'new') router.push('/new-group');
            if (id === 'join') router.push('/join');
          }}
        >
          <View style={{ paddingRight: 12 }}>
            <Symbol sf="plus" ion="add" size={22} color={tokens.foreground} />
          </View>
        </AnchorMenu>
        <CurrentUserAvatar uri={user?.avatarUrl} />
      </View>
      {error ? <ErrorMessage message={error} onRetry={() => void load()} /> : (
        <ScrollView
          style={{ marginTop: 12, flex: 1 }}
          refreshControl={<RefreshControl refreshing={refreshing} onRefresh={() => void load(true)} />}
        >
          <View style={{ gap: 10, paddingBottom: 32 }}>
            {groups.map(group => (
              <GroupCard key={group.id} group={group} onPress={() => void openGroup(group.id)} />
            ))}
          </View>
        </ScrollView>
      )}
    </Screen>
  );
}

const styles = StyleSheet.create({
  header: { flexDirection: 'row', alignItems: 'center', paddingHorizontal: 16, paddingTop: 16 }
});
