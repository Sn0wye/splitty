import { ActionSheetIOS, Alert, Platform } from 'react-native';

/** Swift `.confirmationDialog` — an action sheet, not a modal alert. */
export function presentConfirmationDialog(options: {
  title: string;
  message: string;
  confirmTitle?: string;
  onConfirm: () => void;
}): void {
  const confirmTitle = options.confirmTitle ?? 'Delete';
  if (Platform.OS === 'ios') {
    ActionSheetIOS.showActionSheetWithOptions(
      {
        title: options.title,
        message: options.message,
        options: [confirmTitle, 'Cancel'],
        destructiveButtonIndex: 0,
        cancelButtonIndex: 1
      },
      index => {
        if (index === 0) options.onConfirm();
      }
    );
    return;
  }
  Alert.alert(options.title, options.message, [
    { text: 'Cancel', style: 'cancel' },
    { text: confirmTitle, style: 'destructive', onPress: options.onConfirm }
  ]);
}
