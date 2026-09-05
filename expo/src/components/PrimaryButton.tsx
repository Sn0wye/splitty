import React, { useEffect } from 'react';
import { ActivityIndicator, Text } from 'react-native';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';
import { PressableScale } from '@/components/PressableScale';
import { useReducedMotion } from '@/hooks/useReducedMotion';
import { useTokens } from '@/theme/tokens';

export function PrimaryButton({
  title,
  onPress,
  disabled = false,
  isLoading = false,
  accessibilityLabel,
  testID
}: {
  title: string;
  onPress: () => void;
  disabled?: boolean;
  isLoading?: boolean;
  accessibilityLabel?: string;
  testID?: string;
}): React.JSX.Element {
  const tokens = useTokens();
  const reduced = useReducedMotion();
  const unavailable = disabled || isLoading;
  const opacity = useSharedValue(unavailable ? 0.3 : 1);
  useEffect(() => {
    opacity.value = withTiming(unavailable ? 0.3 : 1, {
      duration: reduced ? 0 : 200,
      easing: Easing.out(Easing.cubic)
    });
  }, [opacity, reduced, unavailable]);
  const fill = useAnimatedStyle(() => ({ opacity: opacity.value }));
  return (
    <PressableScale
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel ?? title}
      accessibilityState={{ disabled: unavailable, busy: isLoading }}
      testID={testID}
      disabled={unavailable}
      scale={0.97}
      onPress={onPress}
      className="w-full"
    >
      <Animated.View
        pointerEvents="none"
        style={[
          {
            position: 'absolute',
            inset: 0,
            borderRadius: 26,
            backgroundColor: tokens.expenseAccent
          },
          fill
        ]}
      />
      <Animated.View
        style={{ height: 52, width: '100%', alignItems: 'center', justifyContent: 'center', borderRadius: 26 }}
      >
        {isLoading
          ? <ActivityIndicator color={tokens.expenseBackground} />
          : <Text style={{ fontSize: 17, fontWeight: '600', color: tokens.expenseBackground }}>{title}</Text>}
      </Animated.View>
    </PressableScale>
  );
}
