import React from 'react';
import { Text, View } from 'react-native';
import { Redirect } from 'expo-router';
import { Screen, Loading } from '@/components/Screen';
import { Symbol } from '@/components/Symbol';
import { useLastGroup } from '@/nav/LastGroupContext';
import { useTokens } from '@/theme/tokens';

export default function GroupTabHome(): React.JSX.Element {
  const { groupId, ready } = useLastGroup();
  const tokens = useTokens();
  if (!ready) return <Loading />;
  if (groupId) return <Redirect href={`/group/${groupId}`} />;
  return (
    <Screen edges={['top']}>
      <View className="flex-1 items-center justify-center">
        <Symbol sf="person.2" ion="people-outline" size={32} color={tokens.foreground} weight="light" />
        <Text className="mt-2 text-[17px] font-semibold text-foreground dark:text-foreground-dark">No group selected</Text>
        <Text className="mt-1 text-[15px] text-muted-foreground dark:text-muted-foreground-dark">Pick a group from the Groups tab.</Text>
      </View>
    </Screen>
  );
}
