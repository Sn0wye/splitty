import React, { useEffect, useRef, useState } from 'react';
import { Dimensions, Keyboard, Platform, ScrollView, Text, TextInput, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { router, Stack } from 'expo-router';
import { PressableScale } from '@/components/PressableScale';
import { Symbol } from '@/components/Symbol';
import { PrimaryButton } from '@/components/UI';
import { useExpenseForm } from '@/expense/ExpenseFormContext';
import { dateRowLabel } from '@/logic/copy';
import { formatCents } from '@/logic/money';
import { useTokens } from '@/theme/tokens';
import type { SFSymbol } from 'expo-symbols';
import type { ComponentProps } from 'react';
import { Ionicons } from '@expo/vector-icons';

function DetailRow({
  sf,
  ion,
  body,
  onPress
}: {
  sf: SFSymbol;
  ion: ComponentProps<typeof Ionicons>['name'];
  body: React.ReactNode;
  onPress?: () => void;
}): React.JSX.Element {
  const tokens = useTokens();
  const inner = (
    <View style={{ flexDirection: 'row', alignItems: 'center', borderRadius: 14, paddingHorizontal: 16, paddingVertical: 12, backgroundColor: `${tokens.expenseForeground}12` }}>
      <View style={{ width: 24, alignItems: 'center' }}>
        <Symbol sf={sf} ion={ion} size={16} color="#8E8E93" />
      </View>
      <View style={{ marginLeft: 14, flex: 1 }}>{body}</View>
      {onPress ? <Symbol sf="chevron.right" ion="chevron-forward" size={12} color="#8E8E93" /> : null}
    </View>
  );
  return onPress ? <PressableScale scale={0.98} onPress={onPress}>{inner}</PressableScale> : inner;
}

export default function ExpenseDetails(): React.JSX.Element {
  const tokens = useTokens();
  const form = useExpenseForm();
  const insets = useSafeAreaInsets();
  const descRef = useRef<TextInput>(null);
  const [keyboardHeight, setKeyboardHeight] = useState(0);
  useEffect(() => {
    const timer = setTimeout(() => descRef.current?.focus(), 400);
    const showEvent = Platform.OS === 'ios' ? 'keyboardWillChangeFrame' : 'keyboardDidShow';
    const hideEvent = Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide';
    const show = Keyboard.addListener(showEvent, event => {
      setKeyboardHeight(Math.max(0, Dimensions.get('window').height - event.endCoordinates.screenY));
    });
    const hide = Keyboard.addListener(hideEvent, () => setKeyboardHeight(0));
    return () => {
      clearTimeout(timer);
      show.remove();
      hide.remove();
    };
  }, []);
  return (
    <View style={{ flex: 1, backgroundColor: tokens.expenseBackground }}>
      <Stack.Screen options={{ title: formatCents(form.totalCents) }} />
      <ScrollView keyboardShouldPersistTaps="handled" contentContainerStyle={{ paddingHorizontal: 20, paddingTop: 20, gap: 12 }}>
        <DetailRow sf="text.alignleft" ion="text-outline" body={(
          <TextInput
            ref={descRef}
            accessibilityLabel="What was it for?"
            testID="expense.description"
            placeholder="What was it for?"
            placeholderTextColor="#8E8E93"
            value={form.description}
            onChangeText={form.setDescription}
            style={{ color: tokens.expenseForeground, fontSize: 17 }}
          />
        )} />
        <DetailRow
          sf="person.2"
          ion="people-outline"
          onPress={() => router.push(`/group/${form.group.id}/new-expense/split`)}
          body={<Text style={{ fontSize: 15, color: tokens.expenseForeground }}>{form.summary}</Text>}
        />
        <DetailRow
          sf="calendar"
          ion="calendar-outline"
          onPress={() => {
            Keyboard.dismiss();
            router.push(`/group/${form.group.id}/new-expense/date`);
          }}
          body={<Text style={{ fontSize: 15, color: tokens.expenseForeground }}>{dateRowLabel(form.date)}</Text>}
        />
        {form.blocking ? <Text style={{ marginTop: 4, fontSize: 15, color: '#FF9500' }}>{form.blocking}</Text> : null}
        {form.saveError ? <Text style={{ marginTop: 4, textAlign: 'center', fontSize: 15, color: tokens.red }}>{form.saveError}</Text> : null}
      </ScrollView>
      <View style={{ paddingHorizontal: 20, paddingTop: 8, paddingBottom: keyboardHeight > 0 ? keyboardHeight + 12 : Math.max(insets.bottom, 12), backgroundColor: tokens.expenseBackground }}>
        <PrimaryButton title="Save" testID="expense.save" isLoading={form.busy} disabled={!form.canSave} onPress={() => void form.save()} />
      </View>
    </View>
  );
}
