import React from 'react';
import { StyleSheet, View } from 'react-native';
import { Redirect, Tabs } from 'expo-router';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { hapticSelection } from '@/haptics';
import { useAuth } from '@/auth/AuthContext';
import { Loading } from '@/components/Screen';
import { PressableScale } from '@/components/PressableScale';
import { Symbol } from '@/components/Symbol';
import { useLastGroup } from '@/nav/LastGroupContext';
import { useNavigationColors } from '@/nav/theme';

export default function TabsLayout(): React.JSX.Element {
  const { signedIn, loading } = useAuth();
  const colors = useNavigationColors();
  const { groupId } = useLastGroup();
  const insets = useSafeAreaInsets();
  if (loading) return <Loading />;
  if (!signedIn) return <Redirect href="/login" />;
  return (
    <Tabs screenOptions={{
      tabBarActiveTintColor: colors.tint,
      tabBarInactiveTintColor: colors.tabInactive,
      tabBarShowLabel: false,
      tabBarBackground: () => <View style={{ flex: 1, backgroundColor: colors.background }} />,
      tabBarButton: ({ children, onPress, style, accessibilityState, testID }) => (
        <PressableScale
          accessibilityRole="button"
          accessibilityState={accessibilityState}
          testID={testID}
          scale={0.88}
          style={style}
          onPress={event => {
            hapticSelection();
            onPress?.(event);
          }}
        >
          {children}
        </PressableScale>
      ),
      tabBarStyle: {
        height: 44 + insets.bottom,
        paddingTop: 12,
        paddingBottom: Math.max(insets.bottom, 4),
        paddingHorizontal: 8,
        backgroundColor: colors.background,
        borderTopWidth: StyleSheet.hairlineWidth,
        borderTopColor: colors.border,
        elevation: 0
      },
      headerShown: false
    }}>
      <Tabs.Screen name="index" options={{
        title: 'Groups',
        tabBarIcon: ({ color, focused }) => <Symbol sf="square.grid.2x2" ion="grid-outline" size={20} color={color} weight={focused ? 'semibold' : 'regular'} />
      }} />
      <Tabs.Screen name="group" options={{
        title: 'Group',
        href: groupId ? `/group/${groupId}` : '/group',
        tabBarIcon: ({ color, focused }) => <Symbol sf="person.2" ion="people-outline" size={20} color={color} weight={focused ? 'semibold' : 'regular'} />
      }} />
      <Tabs.Screen name="settings" options={{
        title: 'Settings',
        tabBarIcon: ({ color, focused }) => <Symbol sf="gearshape" ion="settings-outline" size={20} color={color} weight={focused ? 'semibold' : 'regular'} />
      }} />
    </Tabs>
  );
}
