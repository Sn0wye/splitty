import React, { useState } from 'react';
import { Image, View } from 'react-native';
import { Symbol } from '@/components/Symbol';
import { useTokens } from '@/theme/tokens';

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
  const tokens = useTokens();
  const [failedUri, setFailedUri] = useState<string | null>(null);
  const failed = Boolean(uri && failedUri === uri);

  if (uri && !failed) {
    return (
      <Image
        accessibilityLabel={name ? `${name} avatar` : 'Avatar'}
        source={{ uri }}
        onError={() => setFailedUri(uri)}
        style={{ width: size, height: size, borderRadius: size / 2 }}
      />
    );
  }

  return (
    <View style={{ width: size, height: size, alignItems: 'center', justifyContent: 'center' }}>
      <Symbol
        sf={failed ? 'person.crop.circle.badge.exclamationmark' : 'person.crop.circle.fill'}
        ion={failed ? 'person-circle-outline' : 'person-circle'}
        size={size}
        color={tokens.mutedForeground}
      />
    </View>
  );
}

export function CurrentUserAvatar({ uri, size = SIZE }: { uri?: string | null; size?: number }): React.JSX.Element {
  return <Avatar name="You" uri={uri} size={size} />;
}
