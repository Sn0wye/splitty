import { Platform } from 'react-native';
import * as Haptics from 'expo-haptics';

export function hapticSelection(): void {
  void Haptics.selectionAsync();
}

export function hapticSuccess(): void {
  void Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
}

/** Keypad: Swift `.impact(flexibility: .soft, intensity: 0.4)`. Intensity is not exposed. */
export function hapticSoft(): void {
  if (Platform.OS === 'android') {
    void Haptics.performAndroidHapticsAsync(Haptics.AndroidHaptics.Keyboard_Tap);
    return;
  }
  void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Soft);
}

/** Swipe-delete commit: Swift `.impact(flexibility: .rigid)`. */
export function hapticRigid(): void {
  if (Platform.OS === 'android') {
    void Haptics.performAndroidHapticsAsync(Haptics.AndroidHaptics.Confirm);
    return;
  }
  void Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Rigid);
}
