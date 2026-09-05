import React from 'react';
import { Text, View } from 'react-native';
import { PressableScale } from '@/components/PressableScale';

export function ActionButton({
  title,
  onPress,
  filled = false,
  disabled = false
}: {
  title: string;
  onPress: () => void;
  filled?: boolean;
  disabled?: boolean;
}): React.JSX.Element {
  return (
    <PressableScale
      accessibilityRole="button"
      accessibilityLabel={title}
      accessibilityState={{ disabled }}
      disabled={disabled}
      scale={0.94}
      onPress={onPress}
    >
      <View className={`rounded-[20px] px-4 py-2 ${filled ? 'bg-foreground dark:bg-foreground-dark' : 'bg-muted dark:bg-muted-dark'} ${disabled ? 'opacity-40' : ''}`}>
        <Text className={`text-[14px] font-medium ${filled ? 'text-background dark:text-background-dark' : 'text-foreground dark:text-foreground-dark'}`}>{title}</Text>
      </View>
    </PressableScale>
  );
}
