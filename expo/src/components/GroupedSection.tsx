import React, { Children, type ReactNode } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import { grouped, useTokens } from '@/theme/tokens';

export function GroupedSection({
  header,
  footer,
  footerColor,
  children
}: {
  header?: string;
  footer?: string;
  footerColor?: string;
  children: ReactNode;
}): React.JSX.Element {
  const tokens = useTokens();
  const items = Children.toArray(children).filter(Boolean);
  return (
    <View style={styles.section}>
      {header ? (
        <Text style={[styles.header, { color: tokens.mutedForeground }]}>{header}</Text>
      ) : null}
      <View style={[styles.card, { backgroundColor: tokens.card }]}>
        {items.map((child, index) => (
          <View
            key={index}
            style={index < items.length - 1 ? { borderBottomWidth: StyleSheet.hairlineWidth, borderBottomColor: tokens.border } : undefined}
          >
            {child}
          </View>
        ))}
      </View>
      {footer ? (
        <Text style={[styles.footer, { color: footerColor ?? tokens.mutedForeground }]}>{footer}</Text>
      ) : null}
    </View>
  );
}

export function GroupedRow({
  children,
  paddingHorizontal = 20
}: {
  children: ReactNode;
  paddingHorizontal?: number;
}): React.JSX.Element {
  return <View style={[styles.row, { paddingHorizontal }]}>{children}</View>;
}

const styles = StyleSheet.create({
  section: { marginHorizontal: grouped.sideInset, marginTop: 24 },
  header: { fontSize: 13, marginBottom: 8, marginLeft: 4 },
  card: { borderRadius: grouped.cornerRadius, overflow: 'hidden' },
  footer: { fontSize: 13, marginTop: 8, marginHorizontal: 4 },
  row: { minHeight: 44, paddingVertical: 12, flexDirection: 'row', alignItems: 'center' }
});
