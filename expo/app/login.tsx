import React, { useState } from 'react';
import { Image, Text, View } from 'react-native';
import { Redirect } from 'expo-router';
import { useAuth } from '@/auth/AuthContext';
import { getGoogleServerAuthCode, googleWebClientId, isGoogleCancel } from '@/auth/googleSignIn';
import { DevSignInMenu } from '@/components/DevSignInMenu';
import { GoogleMark } from '@/components/GoogleMark';
import { PressableScale } from '@/components/PressableScale';
import { Loading, Screen } from '@/components/Screen';
import { Symbol } from '@/components/Symbol';
import { Spinner } from '@/components/UI';
import { loginErrorMessage } from '@/logic/copy';

export default function Login(): React.JSX.Element {
  const { signInDev, signInGoogle, signedIn, loading } = useAuth();
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const googleConfigured = Boolean(googleWebClientId());
  if (loading) return <Loading />;
  if (signedIn) return <Redirect href="/(tabs)" />;

  const google = async () => {
    setError('');
    setBusy(true);
    try {
      await signInGoogle(await getGoogleServerAuthCode());
    } catch (caught) {
      if (isGoogleCancel(caught)) return;
      const message = loginErrorMessage(caught);
      if (message) setError(message);
    } finally {
      setBusy(false);
    }
  };

  const submit = async (value: string) => {
    setError('');
    setBusy(true);
    try {
      await signInDev(value);
    } catch (caught) {
      const message = loginErrorMessage(caught);
      if (message) setError(message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Screen backgroundColor="#000000" edges={['top', 'bottom']}>
      <View style={{ flex: 1 }}>
        <View style={{ flex: 1 }} />
        <View style={{ alignItems: 'center' }}>
          <Image source={require('../assets/logo.png')} style={{ width: 96, height: 96 }} resizeMode="contain" accessibilityLabel="Splitty logo" />
          <Text style={{ marginTop: 12, fontSize: 34, fontWeight: '600', color: '#FFFFFF' }}>Splitty</Text>
          <Text style={{ marginTop: 12, fontSize: 15, color: 'rgba(255,255,255,0.6)' }}>Split expenses, settle up.</Text>
        </View>
        <View style={{ flex: 2 }} />
        <View style={{ paddingHorizontal: 20, paddingBottom: 50 }}>
          {error ? <Text accessibilityRole="alert" style={{ marginBottom: 16, textAlign: 'left', fontSize: 13, color: '#FF3B30' }}>{error}</Text> : null}
          <PressableScale accessibilityRole="button" accessibilityLabel="Sign in with Google" disabled={busy} onPress={() => void google()} scale={0.97}>
            <View style={{ height: 50, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', borderRadius: 25, backgroundColor: '#FFFFFF' }}>
              {busy ? <Spinner /> : (
                <>
                  <GoogleMark size={18} />
                  <Text style={{ marginLeft: 10, fontWeight: '500', color: '#000000' }}>Sign in with Google</Text>
                </>
              )}
            </View>
          </PressableScale>
          <View style={{ marginTop: 16 }}>
            <View style={{ height: 50, flexDirection: 'row', alignItems: 'center', justifyContent: 'center', borderRadius: 25, backgroundColor: '#FFFFFF', opacity: 0.4 }}>
              <Symbol sf="apple.logo" ion="logo-apple" size={18} color="#000000" />
              <Text style={{ marginLeft: 10, fontWeight: '500', color: '#000000' }}>Sign in with Apple</Text>
            </View>
            <Text style={{ marginTop: 6, textAlign: 'center', fontSize: 12, color: 'rgba(255,255,255,0.4)' }}>Coming soon</Text>
          </View>
          {__DEV__ ? (
            <View style={{ marginTop: 16, paddingTop: 8 }}>
              <DevSignInMenu disabled={busy} onPick={email => void submit(email)} />
            </View>
          ) : null}
          {!googleConfigured ? <Text style={{ marginTop: 12, textAlign: 'center', fontSize: 12, color: 'rgba(255,255,255,0.4)' }}>Google sign-in needs EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID.</Text> : null}
        </View>
      </View>
    </Screen>
  );
}
