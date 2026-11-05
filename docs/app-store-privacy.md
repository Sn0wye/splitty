# App Store privacy answers

What to enter in App Store Connect under App Privacy, and the URLs it asks for. The answers
mirror `Splitty/Splitty/PrivacyInfo.xcprivacy` and the website's privacy policy
(`web/src/legal/*/privacy.md`). Change all three together.

## URLs

| Field | Value |
|---|---|
| Privacy Policy URL | `https://<domain>/privacy` |
| Support URL | `https://<domain>/support` |
| Marketing URL (optional) | `https://<domain>/` |

The pages exist in every app language: `/pt-br/privacy`, `/es/privacy`, `/fr/privacy`.
App Store Connect takes one URL per localization, so each localized listing can point at its
own language.

## Tracking

**Do you or your third-party partners use data for tracking?** No. There are no ads, no
analytics SDK and no data brokers. `NSPrivacyTracking` is `false`.

## Data collected

Every type below is used for **App Functionality** only and is **not used for tracking**.

| Category | Type | Linked to the user | What it is |
|---|---|---|---|
| Contact Info | Name | Yes | From Google at sign-in, editable in Profile |
| Contact Info | Email Address | Yes | From Google at sign-in, shown to group members |
| User Content | Photos or Videos | Yes | The profile photo a user uploads (stored in R2) |
| User Content | Other User Content | Yes | Groups, expenses, payments, invites |
| Financial Info | Other Financial Info | Yes | Amounts and debts users enter. Splitty never sees bank or card data |
| Identifiers | User ID | Yes | The Splitty account id and the Google subject |
| Identifiers | Device ID | Yes | The APNs push token, stored only while the device is signed in |
| Other Data | Other Data Types | Yes | The app language and notification settings, so pushes arrive in that language and only of the kinds the user kept |
| Diagnostics | Crash Data | No | MetricKit crash reports, sent without the account |
| Diagnostics | Performance Data | No | MetricKit hang reports, sent without the account |
| Diagnostics | Other Diagnostic Data | No | 5xx and decoding failures with their trace id |

## Not collected

Location, Contacts, Health and Fitness, Browsing History, Search History, Purchases, Usage
Data, Sensitive Info, Payment Info, Credit Info, Audio, Gameplay and Customer Support data.
The theme stays on the device and never reaches the server, so it is not "collected" in
Apple's sense. The language reaches the server with the push token once notifications are on.

Push notifications go through Apple's APNs. Their text (group name, a member's name, an
expense description and an amount) is user content already declared above.

## When this changes

Adding Sign in with Apple, an analytics SDK, or anything else that sends new data off the
device means updating the manifest, this table, the four privacy policies and the App Store
Connect answers in the same change.
