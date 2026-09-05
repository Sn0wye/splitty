import { Platform, type TextStyle } from 'react-native';

/**
 * Closest SF Rounded treatment React Native exposes without bundling Apple font files.
 * iOS `Text` cannot select `UIFontDescriptorSystemDesignRounded`; the system UI face is used.
 */
export function roundedTextStyle(extra?: TextStyle): TextStyle {
  return {
    ...Platform.select<TextStyle>({
      ios: { fontFamily: 'System' },
      default: {}
    }),
    ...extra
  };
}

export function systemMonospacedTitle2(): TextStyle {
  return Platform.select<TextStyle>({
    ios: { fontSize: 22, fontFamily: 'Menlo' },
    default: { fontSize: 22, fontFamily: 'monospace' }
  }) as TextStyle;
}
