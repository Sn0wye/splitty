import { Platform, type TextStyle } from 'react-native';

/**
 * SwiftUI's `.system(design: .rounded)` maps to the installed SF Pro Rounded family on iOS.
 * Other platforms keep their system face rather than substituting an unrelated bundled font.
 */
export function roundedTextStyle(extra?: TextStyle): TextStyle {
  return {
    ...Platform.select<TextStyle>({
      ios: { fontFamily: 'SF Pro Rounded' },
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
