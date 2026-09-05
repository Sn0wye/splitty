import { Platform } from 'react-native';

export class GoogleSignInUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'GoogleSignInUnavailableError';
  }
}

export function googleWebClientId(): string | undefined {
  const value = process.env.EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID?.trim();
  return value ? value : undefined;
}

/**
 * Native Google Sign-In mints a one-time server auth code for the *web* client,
 * with no redirect URI — the same contract as GIDSignIn.serverAuthCode and
 * GoogleTokenExchanger (redirect_uri: "").
 *
 * Expo AuthSession codes are bound to a native/web redirect and will be rejected
 * by that exchange. Do not use AuthSession for production Google sign-in.
 */
export async function getGoogleServerAuthCode(): Promise<string> {
  const webClientId = googleWebClientId();
  if (!webClientId) {
    throw new GoogleSignInUnavailableError('Google sign-in is not configured. Set EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID to the same web client the API uses as Google:ClientId.');
  }
  if (Platform.OS === 'web') {
    throw new GoogleSignInUnavailableError('Google sign-in on web is not supported. The API exchanges a native server auth code with an empty redirect_uri.');
  }

  try {
    const { GoogleSignin } = require('@react-native-google-signin/google-signin') as typeof import('@react-native-google-signin/google-signin');
    GoogleSignin.configure({
      webClientId,
      iosClientId: process.env.EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID || undefined,
      offlineAccess: true,
      forceCodeForRefreshToken: true,
      scopes: ['openid', 'profile', 'email']
    });
    if (Platform.OS === 'android') {
      await GoogleSignin.hasPlayServices({ showPlayServicesUpdateDialog: true });
    }
    const result = await GoogleSignin.signIn();
    if (result.type === 'cancelled') {
      throw new GoogleSignInUnavailableError('cancelled');
    }
    const code = result.type === 'success' ? result.data.serverAuthCode : null;
    if (!code) {
      throw new GoogleSignInUnavailableError('Google did not return a server authorization code. Confirm GIDServerClientID / webClientId is the API web client, offline access is enabled, and the iOS URL scheme is the reversed iOS client ID.');
    }
    return code;
  } catch (error) {
    if (isGoogleCancel(error)) throw new GoogleSignInUnavailableError('cancelled');
    if (error instanceof GoogleSignInUnavailableError) throw error;
    const message = error instanceof Error ? error.message : String(error);
    if (message.includes('native module') || message.includes('RNGoogleSignin') || message.includes('Expo Go')) {
      throw new GoogleSignInUnavailableError('Google sign-in needs a development build (`bun run ios` / `bun run android`). Expo Go cannot mint the server authorization code the API redeems.');
    }
    throw error;
  }
}

export function isGoogleCancel(error: unknown): boolean {
  if (error instanceof GoogleSignInUnavailableError && error.message === 'cancelled') return true;
  if (error && typeof error === 'object' && 'code' in error) {
    const code = String((error as { code: unknown }).code);
    return code.includes('CANCEL') || code.includes('cancel') || code === '12501';
  }
  return false;
}
