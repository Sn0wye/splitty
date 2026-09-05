import React from 'react';
import { Text, View } from 'react-native';
import { AnchorMenu } from '@/components/AnchorMenu';
import { Symbol } from '@/components/Symbol';

const seededEmails = [
  'john@example.com',
  'jane@example.com',
  'bob@example.com',
  'alice@example.com',
  'charlie@example.com',
  'eva@example.com'
];

export function DevSignInMenu({
  disabled,
  onPick
}: {
  disabled: boolean;
  onPick: (email: string) => void;
}): React.JSX.Element {
  return (
    <AnchorMenu
      disabled={disabled}
      accessibilityLabel="Dev sign in"
      actions={seededEmails.map(email => ({ id: email, title: email }))}
      onAction={onPick}
    >
      <View style={{ height: 50, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', borderRadius: 25, borderWidth: 1, borderColor: 'rgba(142,142,147,0.3)', backgroundColor: 'rgba(142,142,147,0.2)', opacity: disabled ? 0.4 : 1 }}>
        <Symbol sf="hammer" ion="hammer-outline" size={16} color="#FFFFFF" />
        <Text style={{ marginLeft: 8, fontWeight: '500', color: '#FFFFFF' }}>Dev sign in</Text>
      </View>
    </AnchorMenu>
  );
}
