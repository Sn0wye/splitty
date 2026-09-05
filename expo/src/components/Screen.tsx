import React from 'react';
import { ActivityIndicator, KeyboardAvoidingView, Platform, ScrollView, Text, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useTokens } from '@/theme/tokens';

type Edge = 'top' | 'bottom' | 'left' | 'right';

export function Screen({
  children,
  scroll = false,
  edges = ['top', 'bottom'],
  className,
  padded = false,
  backgroundColor
}: {
  children: React.ReactNode;
  scroll?: boolean;
  edges?: Edge[];
  className?: string;
  padded?: boolean;
  backgroundColor?: string;
}): React.JSX.Element {
  const tokens = useTokens();
  const bg = backgroundColor ?? tokens.background;
  const body = <View className={`flex-1 ${padded ? 'px-5' : ''} ${className ?? ''}`} style={{ backgroundColor: bg }}>{children}</View>;
  return (
    <SafeAreaView className="flex-1" style={{ flex: 1, backgroundColor: bg }} edges={edges}>
      <KeyboardAvoidingView className="flex-1" behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
        {scroll ? <ScrollView className="flex-1" keyboardShouldPersistTaps="handled" contentContainerClassName="flex-grow pb-6">{body}</ScrollView> : body}
      </KeyboardAvoidingView>
    </SafeAreaView>
  );
}

export function Loading({ label = 'Loading...' }: { label?: string }): React.JSX.Element {
  const tokens = useTokens();
  return (
    <View className="flex-1 items-center justify-center" style={{ backgroundColor: tokens.background }}>
      <ActivityIndicator color={tokens.foreground} />
      <Text className="mt-3" style={{ color: tokens.foreground }}>{label}</Text>
    </View>
  );
}
