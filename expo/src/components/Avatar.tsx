import React from 'react';
import { Image, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';

const SIZE = 40;

export function Avatar({
  uri,
  name,
  size = SIZE
}: {
  uri?: string | null;
  name?: string;
  size?: number;
}): React.JSX.Element {
  if (uri) {
    return (
      <Image
        accessibilityLabel={name ? `${name} avatar` : 'Avatar'}
        source={{ uri }}
        style={{ width: size, height: size, borderRadius: size / 2 }}
      />
    );
  }
  return (
    <View style={{ width: size, height: size }} className="items-center justify-center">
      <Ionicons name="person-circle" size={size} color="#9ca3af" />
    </View>
  );
}

export function CurrentUserAvatar({ uri, size = SIZE }: { uri?: string | null; size?: number }): React.JSX.Element {
  return <Avatar name="You" uri={uri} size={size} />;
}
