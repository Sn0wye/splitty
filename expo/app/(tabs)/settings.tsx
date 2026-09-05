import React from 'react';
import { Alert, Text } from 'react-native';
import { useAuth } from '@/auth/AuthContext';
import { GroupedRow, GroupedSection } from '@/components/GroupedSection';
import { Screen } from '@/components/Screen';
import { Symbol } from '@/components/Symbol';
import { PressableScale } from '@/components/PressableScale';
import { useTokens } from '@/theme/tokens';

export default function Settings(): React.JSX.Element {
  const { signOut } = useAuth();
  const tokens = useTokens();
  return (
    <Screen edges={['top']}>
      <Text style={{ paddingHorizontal: 16, paddingBottom: 12, paddingTop: 8, fontSize: 34, fontWeight: '700', color: tokens.foreground }}>Settings</Text>
      <GroupedSection header="Account">
        <PressableScale
          accessibilityRole="button"
          accessibilityLabel="Log Out"
          onPress={() => Alert.alert('Log Out', 'Are you sure you want to log out?', [
            { text: 'Cancel', style: 'cancel' },
            { text: 'Log Out', style: 'destructive', onPress: () => { void signOut(); } }
          ])}
        >
          <GroupedRow>
            <Symbol sf="rectangle.portrait.and.arrow.right" ion="log-out-outline" size={20} color={tokens.red} />
            <Text style={{ marginLeft: 12, fontSize: 17, color: tokens.red }}>Log Out</Text>
          </GroupedRow>
        </PressableScale>
      </GroupedSection>
    </Screen>
  );
}
