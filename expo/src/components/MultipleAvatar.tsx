import React from 'react';
import { View } from 'react-native';
import { Avatar } from '@/components/Avatar';

export function MultipleAvatar({
  members,
  size = 40
}: {
  members: { name: string; avatarUrl?: string | null }[];
  size?: number;
}): React.JSX.Element {
  if (members.length === 0) return <Avatar name="Group" size={size} />;
  return (
    <View className="flex-row items-center" style={{ flexDirection: 'row', alignItems: 'center' }}>
      {members.map((member, index) => (
        <View key={`${member.name}-${index}`} style={{ marginLeft: index === 0 ? 0 : -12, zIndex: index }}>
          <Avatar name={member.name} uri={member.avatarUrl} size={size} />
        </View>
      ))}
    </View>
  );
}
