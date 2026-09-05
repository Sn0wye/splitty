const iosClientId = process.env.EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID ?? '';
const webClientId = process.env.EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID ?? '';

function reversedGoogleIosScheme(clientId) {
  if (!clientId.endsWith('.apps.googleusercontent.com')) return undefined;
  return clientId.split('.').reverse().join('.');
}

const iosUrlScheme = reversedGoogleIosScheme(iosClientId);

module.exports = {
  expo: {
    name: 'Splitty',
    slug: 'splitty',
    version: '1.0.0',
    orientation: 'portrait',
    scheme: 'splitty',
    userInterfaceStyle: 'automatic',
    newArchEnabled: true,
    icon: './assets/icon.png',
    plugins: [
      'expo-router',
      ['expo-splash-screen', {
        backgroundColor: '#000000',
        image: './assets/splash-icon.png',
        imageWidth: 192,
        resizeMode: 'contain',
        dark: {
          backgroundColor: '#000000',
          image: './assets/splash-icon.png'
        }
      }],
      'expo-secure-store',
      'expo-font',
      'expo-status-bar',
      '@react-native-community/datetimepicker',
      ...(iosUrlScheme ? [['@react-native-google-signin/google-signin', { iosUrlScheme }]] : [])
    ],
    experiments: { typedRoutes: true },
    ios: {
      supportsTablet: true,
      bundleIdentifier: 'com.splitty.app',
      icon: {
        light: './assets/icon.png',
        dark: './assets/icon-dark.png',
        tinted: './assets/icon-tinted.png'
      },
      infoPlist: {
        ...(iosClientId ? { GIDClientID: iosClientId } : {}),
        ...(webClientId ? { GIDServerClientID: webClientId } : {})
      }
    },
    android: {
      package: 'com.splitty.app',
      adaptiveIcon: {
        foregroundImage: './assets/adaptive-icon.png',
        monochromeImage: './assets/icon-tinted.png',
        backgroundColor: '#000000'
      }
    }
  }
};
