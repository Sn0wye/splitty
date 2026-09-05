import React, { useRef } from 'react';
import { StyleSheet } from 'react-native';
import { Swipeable } from 'react-native-gesture-handler';
import { hapticRigid } from '@/haptics';
import { PressableScale } from '@/components/PressableScale';
import { Symbol } from '@/components/Symbol';
import { useTokens } from '@/theme/tokens';

export function SwipeToDeleteRow({
  children,
  onDelete,
  onPress,
  accessibilityLabel
}: {
  children: React.ReactNode;
  onDelete: () => void;
  onPress: () => void;
  accessibilityLabel: string;
}): React.JSX.Element {
  const swipeable = useRef<Swipeable>(null);
  const tokens = useTokens();
  const confirm = () => {
    hapticRigid();
    swipeable.current?.close();
    onDelete();
  };
  return (
    <Swipeable
      ref={swipeable}
      overshootRight={false}
      onSwipeableOpen={confirm}
      renderRightActions={() => (
        <PressableScale accessibilityRole="button" accessibilityLabel="Delete" scale={1} onPress={confirm} style={[styles.delete, { backgroundColor: tokens.red }]}>
          <Symbol sf="trash" ion="trash" size={20} color="#FFFFFF" />
        </PressableScale>
      )}
    >
      <PressableScale
        accessibilityRole="button"
        accessibilityLabel={accessibilityLabel}
        accessibilityActions={[{ name: 'delete', label: 'Delete' }]}
        onAccessibilityAction={event => { if (event.nativeEvent.actionName === 'delete') confirm(); }}
        scale={1}
        pressedOpacity={1}
        onPress={onPress}
        style={{ backgroundColor: tokens.card }}
      >
        {children}
      </PressableScale>
    </Swipeable>
  );
}

const styles = StyleSheet.create({
  delete: { width: 88, alignItems: 'center', justifyContent: 'center' }
});
