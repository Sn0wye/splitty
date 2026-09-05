# Splitty Expo client

Production React Native client for the Splitty REST API. It uses Expo Router, NativeWind, strict TypeScript, SecureStore JWT persistence, and integer cents in all split calculations.

Native `ios/` and `android/` trees are generated Continuous Native Generation output. They are gitignored. Do not commit them, and do not run a native build against a leftover copy. Expo uses the original Swift app artwork from `assets/` for the app icon, login logo, adaptive icon, and black launch screen.

## Setup

```sh
cd expo
cp .env.example .env
```

Fill `.env` before generating native projects. Google Sign-In needs `EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID` and, for iOS, `EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID` so prebuild can write `GIDClientID`, `GIDServerClientID`, and the reversed-client-id URL scheme. The Google config plugin is included only when that iOS URL scheme can be derived. Autolinking still comes from the npm package.

```sh
bun install
bunx expo prebuild --clean
```

`bunx expo prebuild --clean` (or `npx expo prebuild --clean`) is required before `bun run ios` / `bun run android`. Skipping it reuses a stale generated tree that will not have current Google URL-scheme or Info.plist values.

```sh
bun run start
```

Set `EXPO_PUBLIC_API_BASE_URL` to the API host. Use `http://localhost:8080` in the iOS simulator and `http://10.0.2.2:8080` in the Android emulator. Start the local API and seed data from the repository instructions first.

Google sign-in is a native module. Use a development build, not Expo Go.

## Authentication

Production sign-in uses **native Google Sign-In** (`@react-native-google-signin/google-signin`), the same contract as the iOS `GIDSignIn` SDK:

1. The app configures `webClientId` as the **server** client (API `Google:ClientId`).
2. The user picks an account.
3. Only `serverAuthCode` is posted to `POST /oauth/google`.
4. The API exchanges that code with `redirect_uri: ""` and the web client secret.

The app never holds a Google client secret and never exchanges the code on device.

### Google Cloud Console

Create three OAuth clients in the same project:

| Client | Use |
|---|---|
| **Web** | API `Google:ClientId` / `Google:ClientSecret` and `EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID`. Enable the “iOS”/Android clients to request offline/server auth codes for this web client. |
| **iOS** | Bundle ID `com.splitty.app`. Set `EXPO_PUBLIC_GOOGLE_IOS_CLIENT_ID`. Add the **reversed** client id (e.g. `com.googleusercontent.apps.123-abc`) as an iOS URL scheme via the config plugin. |
| **Android** | Package `com.splitty.app` plus your keystore SHA-1. |

Do **not** point this flow at an AuthSession / Expo proxy redirect. Those codes are issued for a native redirect URI and fail `redirect_uri_mismatch` against the API’s empty `redirect_uri`.

Expo Go cannot load the native Google Sign-In module. If `EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID` is unset, the Google button stays disabled instead of pretending to work.

Development builds show **Dev sign in** by default, matching Swift's `#if DEBUG` behavior. Set `EXPO_PUBLIC_ENABLE_DEV_LOGIN=false` to hide it during local development. Release builds never show it, and the backend route is unavailable on production API hosts.

## Commands

```sh
bun run start       # Expo dev server
bunx expo prebuild --clean   # regenerate ios/ and android/ from app.config.js
bun run ios         # native iOS development build (after prebuild)
bun run android     # native Android development build (after prebuild)
bun run typecheck   # strict tsc
bun run test        # pure money, expression, split, timeline tests
bun run lint        # ESLint
```

Money is converted from API decimal values to integer cents immediately. A split's mode remains descriptive and percentage/equal remainders are assigned deterministically to the lowest user IDs. Balance responses are eventually consistent; the UI displays the API's `balancesPending` hint and offers an explicit refresh.

The amount pad is digits, decimal, and backspace, matching the current Swift keypad. `AmountExpression` still understands left-to-right arithmetic for tests and for resolving a pending operator on save.
