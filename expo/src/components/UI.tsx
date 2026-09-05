import React from 'react';
import { ActivityIndicator, Pressable, Text, TextInput, View } from 'react-native';
import { PrimaryButton } from '@/components/PrimaryButton';
import { PressableScale } from '@/components/PressableScale';
import { useTokens } from '@/theme/tokens';

export { Avatar, CurrentUserAvatar } from '@/components/Avatar';
export { MultipleAvatar } from '@/components/MultipleAvatar';
export { PrimaryButton } from '@/components/PrimaryButton';
export { PressableScale } from '@/components/PressableScale';
export { ActionButton } from '@/components/ActionButton';

export function Button({
  title,
  onPress,
  variant = 'primary',
  disabled = false
}: {
  title: string;
  onPress: () => void;
  variant?: 'primary' | 'secondary' | 'danger';
  disabled?: boolean;
}): React.JSX.Element {
  if (variant === 'primary') return <PrimaryButton title={title} onPress={onPress} disabled={disabled} />;
  const bg = variant === 'danger' ? 'bg-negative' : 'bg-muted dark:bg-muted-dark';
  const fg = variant === 'danger' ? 'text-white' : 'text-foreground dark:text-foreground-dark';
  return (
    <PressableScale accessibilityRole="button" accessibilityLabel={title} disabled={disabled} onPress={onPress} scale={0.97}>
      <View className={`h-[52px] items-center justify-center rounded-full px-5 ${bg} ${disabled ? 'opacity-40' : ''}`}>
        <Text className={`font-semibold ${fg}`}>{title}</Text>
      </View>
    </PressableScale>
  );
}

export function Field({
  label,
  value,
  onChangeText,
  placeholder,
  keyboardType = 'default',
  multiline = false,
  autoFocus = false,
  autoCapitalize = 'sentences',
  className = ''
}: {
  label: string;
  value: string;
  onChangeText: (value: string) => void;
  placeholder?: string;
  keyboardType?: 'default' | 'decimal-pad' | 'number-pad' | 'email-address';
  multiline?: boolean;
  autoFocus?: boolean;
  autoCapitalize?: 'none' | 'sentences' | 'words' | 'characters';
  className?: string;
}): React.JSX.Element {
  return (
    <View className="mb-1">
      <Text className="mb-1 text-[13px] text-muted-foreground dark:text-muted-foreground-dark">{label}</Text>
      <TextInput
        accessibilityLabel={label}
        value={value}
        onChangeText={onChangeText}
        placeholder={placeholder}
        placeholderTextColor="#A1A1AA"
        keyboardType={keyboardType}
        multiline={multiline}
        autoFocus={autoFocus}
        autoCapitalize={autoCapitalize}
        className={`py-3 text-[17px] text-foreground dark:text-foreground-dark ${multiline ? 'min-h-[72px]' : ''} ${className}`}
      />
    </View>
  );
}

export function ErrorMessage({ message, onRetry }: { message: string; onRetry?: () => void }): React.JSX.Element {
  const tokens = useTokens();
  return (
    <View style={{ backgroundColor: tokens.card, paddingHorizontal: 20, paddingVertical: 16 }}>
      <Text accessibilityRole="alert" style={{ color: tokens.red }}>{message}</Text>
      {onRetry ? (
        <Pressable accessibilityRole="button" accessibilityLabel="Try again" onPress={onRetry} style={{ marginTop: 12, minHeight: 44, justifyContent: 'center' }}>
          <Text style={{ fontWeight: '600', color: tokens.accent }}>Try again</Text>
        </Pressable>
      ) : null}
    </View>
  );
}

export function Spinner(): React.JSX.Element {
  return <ActivityIndicator accessibilityLabel="Loading" />;
}
