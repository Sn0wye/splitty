import React from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { PressableScale } from '@/components/PressableScale';
import { Symbol } from '@/components/Symbol';
import { groupCardOweLabel } from '@/logic/copy';
import { centsFromApi, formatCents } from '@/logic/money';
import { MultipleAvatar } from '@/components/MultipleAvatar';
import { useTokens } from '@/theme/tokens';
import type { Group } from '@/types';

export function GroupCard({ group, onPress }: { group: Group; onPress: () => void }): React.JSX.Element {
  const tokens = useTokens();
  const cents = centsFromApi(group.netBalance);
  const positive = cents > 0;
  return (
    <PressableScale
      accessibilityRole="button"
      accessibilityLabel={`Open ${group.name}`}
      testID="groups.card"
      scale={0.98}
      onPress={onPress}
    >
      <View style={[styles.card, { backgroundColor: tokens.card }]}>
        <View style={styles.row}>
          <View style={styles.body}>
            <MultipleAvatar members={group.members} />
            <Text style={[styles.name, { color: tokens.foreground }]}>{group.name}</Text>
            <Text style={[styles.status, { color: tokens.foreground }]}>{groupCardOweLabel(cents)}</Text>
            <Text style={[styles.amount, { color: positive ? tokens.green : tokens.red }]}>{formatCents(Math.abs(cents))}</Text>
          </View>
          <Symbol sf="ellipsis" ion="ellipsis-horizontal" size={18} color={tokens.foreground} />
        </View>
      </View>
    </PressableScale>
  );
}

const styles = StyleSheet.create({
  card: { marginHorizontal: 20, borderRadius: 10, padding: 16 },
  row: { flexDirection: 'row', alignItems: 'flex-start' },
  body: { flex: 1, gap: 8 },
  name: { fontSize: 17, fontWeight: '600', paddingBottom: 2 },
  status: { fontSize: 12 },
  amount: { fontSize: 18, fontWeight: '700' }
});
