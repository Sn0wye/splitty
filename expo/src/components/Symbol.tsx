import React from 'react';
import { Platform, type ColorValue } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { SymbolView, type SFSymbol, type SymbolWeight } from 'expo-symbols';

type IonName = React.ComponentProps<typeof Ionicons>['name'];

export function Symbol({
  sf,
  ion,
  size,
  color,
  weight = 'regular'
}: {
  sf: SFSymbol;
  ion: IonName;
  size: number;
  color: ColorValue;
  weight?: SymbolWeight;
}): React.JSX.Element {
  if (Platform.OS === 'ios') {
    return (
      <SymbolView
        name={sf}
        size={size}
        tintColor={color}
        weight={weight}
        type="monochrome"
        fallback={<Ionicons name={ion} size={size} color={color} />}
      />
    );
  }
  return <Ionicons name={ion} size={size} color={color} />;
}
