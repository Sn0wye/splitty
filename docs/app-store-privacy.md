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
| Diagnostics | Crash Data | No | MetricKit crash reports, sent without the account |
| Diagnostics | Performance Data | No | MetricKit hang reports, sent without the account |
| Diagnostics | Other Diagnostic Data | No | 5xx and decoding failures with their trace id |

## Not collected

Location, Contacts, Health and Fitness, Browsing History, Search History, Purchases, Usage
Data, Sensitive Info, Device ID, Payment Info, Credit Info, Audio, Gameplay, Customer Support
data, and Other Data. Theme and language stay on the device and never reach the server, so
they are not "collected" in Apple's sense.

## When this changes

Adding Sign in with Apple, an analytics SDK, push notifications or anything that sends new
data off the device means updating the manifest, this table, the four privacy policies and
the App Store Connect answers in the same change.
