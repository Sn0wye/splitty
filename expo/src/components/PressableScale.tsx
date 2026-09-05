import React, { type ReactNode } from 'react';
import { Pressable, type PressableProps, type StyleProp, type ViewStyle } from 'react-native';
import Animated, { Easing, useAnimatedStyle, useSharedValue, withTiming } from 'react-native-reanimated';
import { useReducedMotion } from '@/hooks/useReducedMotion';

export function PressableScale({
  scale = 0.97,
  pressedOpacity = 0.9,
  style,
  className,
  children,
  onPressIn,
  onPressOut,
  ...rest
}: Omit<PressableProps, 'children'> & { scale?: number; pressedOpacity?: number; style?: StyleProp<ViewStyle>; className?: string; children?: ReactNode }): React.JSX.Element {
  const reduced = useReducedMotion();
  const progress = useSharedValue(0);
  const animated = useAnimatedStyle(() => ({
    transform: [{ scale: 1 + (scale - 1) * progress.value }],
    opacity: 1 + (pressedOpacity - 1) * progress.value
  }));
  return (
    <Pressable
      {...rest}
      className={className}
      onPressIn={event => {
        progress.value = withTiming(1, { duration: reduced ? 0 : 100, easing: Easing.out(Easing.quad) });
        onPressIn?.(event);
      }}
      onPressOut={event => {
        progress.value = withTiming(0, { duration: reduced ? 0 : 200, easing: Easing.out(Easing.quad) });
        onPressOut?.(event);
      }}
      style={style}
    >
      <Animated.View style={animated}>{children}</Animated.View>
    </Pressable>
  );
}
