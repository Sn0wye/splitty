import React from 'react';
import { Pressable, StyleSheet, Text, View } from 'react-native';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';
import { hapticSoft } from '@/haptics';
import { useReducedMotion } from '@/hooks/useReducedMotion';
import { Symbol } from '@/components/Symbol';
import { roundedTextStyle } from '@/theme/fonts';
import { useTokens } from '@/theme/tokens';

const rows: { label: string; a11y: string; key: string }[][] = [
  [{ label: '1', a11y: '1', key: '1' }, { label: '2', a11y: '2', key: '2' }, { label: '3', a11y: '3', key: '3' }],
  [{ label: '4', a11y: '4', key: '4' }, { label: '5', a11y: '5', key: '5' }, { label: '6', a11y: '6', key: '6' }],
  [{ label: '7', a11y: '7', key: '7' }, { label: '8', a11y: '8', key: '8' }, { label: '9', a11y: '9', key: '9' }],
  [{ label: '.', a11y: 'decimal', key: '.' }, { label: '0', a11y: '0', key: '0' }, { label: 'back', a11y: 'delete', key: 'back' }]
];

function Key({
  item,
  onKey
}: {
  item: { label: string; a11y: string; key: string };
  onKey: (key: string) => void;
}): React.JSX.Element {
  const tokens = useTokens();
  const reduced = useReducedMotion();
  const pressed = useSharedValue(0);
  const halo = useAnimatedStyle(() => ({
    opacity: pressed.value * 0.07
  }));
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={item.a11y}
      testID={`keypad.key.${item.key === 'back' ? 'chevron.left' : item.label}`}
      onPressIn={() => {
        hapticSoft();
        pressed.value = withTiming(1, { duration: reduced ? 0 : 80, easing: Easing.out(Easing.quad) });
      }}
      onPressOut={() => {
        pressed.value = withTiming(0, { duration: reduced ? 0 : 200, easing: Easing.out(Easing.quad) });
      }}
      onPress={() => onKey(item.key)}
      style={styles.keyHit}
    >
      <Animated.View
        pointerEvents="none"
        style={[styles.halo, { backgroundColor: tokens.expenseForeground }, halo]}
      />
      {item.key === 'back'
        ? <Symbol sf="chevron.left" ion="chevron-back" size={32} color={tokens.expenseForeground} weight="medium" />
        : (
          <Text style={roundedTextStyle({ fontSize: 32, fontWeight: '500', color: tokens.expenseForeground })}>
            {item.label}
          </Text>
        )}
    </Pressable>
  );
}

export function ExpenseKeypad({ onKey }: { onKey: (key: string) => void }): React.JSX.Element {
  return (
    <View style={styles.pad}>
      {rows.map(row => (
        <View key={row.map(item => item.key).join('-')} style={styles.row}>
          {row.map(item => <Key key={item.key} item={item} onKey={onKey} />)}
        </View>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  pad: { paddingBottom: 8, gap: 2 },
  row: { flexDirection: 'row' },
  keyHit: { flex: 1, height: 68, alignItems: 'center', justifyContent: 'center' },
  halo: { position: 'absolute', width: 72, height: 72, borderRadius: 36 }
});
