import React from 'react';
import { View } from 'react-native';

/** Four-colour Google G, drawn so there is no extra asset. */
export function GoogleMark({ size = 18 }: { size?: number }): React.JSX.Element {
  const width = size * 0.22;
  return (
    <View style={{ width: size, height: size }} accessibilityElementsHidden>
      <View style={{ position: 'absolute', width: size, height: size, borderRadius: size / 2, borderWidth: width, borderTopColor: '#EA4335', borderRightColor: '#FBBC05', borderBottomColor: '#34A853', borderLeftColor: '#4285F4' }} />
      <View style={{ position: 'absolute', right: 0, top: (size - width) / 2, width: size * 0.5, height: width, backgroundColor: '#4285F4' }} />
    </View>
  );
}
