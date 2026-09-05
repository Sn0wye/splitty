import React from 'react';
import { View } from 'react-native';
import { MenuView, type MenuAction } from '@react-native-menu/menu';

export function AnchorMenu({
  actions,
  onAction,
  disabled = false,
  accessibilityLabel,
  children
}: {
  actions: MenuAction[];
  onAction: (id: string) => void;
  disabled?: boolean;
  accessibilityLabel: string;
  children: React.ReactNode;
}): React.JSX.Element {
  return (
    <MenuView
      actions={disabled ? [] : actions}
      onPressAction={({ nativeEvent }) => {
        if (nativeEvent.event) onAction(nativeEvent.event);
      }}
      shouldOpenOnLongPress={false}
    >
      <View accessible accessibilityRole="button" accessibilityLabel={accessibilityLabel} accessibilityState={{ disabled }}>
        {children}
      </View>
    </MenuView>
  );
}
