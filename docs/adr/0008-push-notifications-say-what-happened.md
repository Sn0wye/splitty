# Push notifications say what happened, from APNs directly, in the app's language

Members of a group get a push notification when something in it changes their money: an
expense they are in is added, changed or deleted, a payment to or from them is recorded,
changed or deleted, someone asks them to pay, someone joins with their invite, or they are
removed. Any member may edit anything (invariant 2), and that stays true. A notification
tells people what happened. It is not a feed, an audit trail or an approval step, and nothing
records who was told what.

## Who hears

The person who did it never does. Of the rest, only people whose money moved hear: the payer
and participants of an expense, the two sides of a payment. An edit that changes only the
description, category or date tells no one. Each person gets one sentence about the change
that matters most to them: being added or removed, then their share, then what they paid.

Expenses a recurring expense adds on a group read (ADR 0006) tell no one. They are a side
effect of whoever happened to open the group, at whatever time that was, so the actor and the
moment would both be wrong. Creating the recurring expense is told once.

A user can switch off each kind of notification, and all of them at once with a main switch
that keeps the kinds as they were. The settings live on the user, not the device.

## Built from the write, sent in the background

A write that succeeds decides its notices from the row it wrote, in the service, right where
it requests its recomputation. Nothing reads `Balance`, so the eventually consistent ledger
cannot put a stale amount in a notification. The one exception is the reminder, whose amount
is a simplified debt. It is refused while the group is pending, as leaving is.

Notices go to an in-memory channel and one worker sends them. Unlike the ledger, there is
nothing to recover on start. A notice lost to a restart stays lost, because a notification is
not the record of anything.

## APNs directly, with a .p8 key

The app is iOS only. A provider such as Firebase or OneSignal would add an SDK to an app that
has almost none, and another processor of names and amounts to the privacy policy. Sending to
APNs is one HTTP/2 POST with an ES256 JWT that .NET can sign without a library.
`IPushSender` is the only component that talks to Apple.

## The device belongs to a sign-in

A device token is stored against the refresh token family that registered it (ADR 0005),
named by an `fid` claim in the access token. A push goes only to devices whose family still
has a live token. Logging out, reuse detection, deactivation and expiry all stop pushes with
no further code. Logging out, deactivation and deletion also delete the rows. A token is
unique, so a second user signing in on the same phone takes it over. A token APNs reports
as unregistered is deleted.

## The server writes the text

The language is picked inside the app and stored in its own defaults. iOS renders a
`loc-key` in the system's language, which is often a different one. Currency formats would
also have to be built on the server either way (ADR 0007). So the device sends its language
when it registers and again when the user changes it, and the server keeps the sentences in
the four languages. Re-rendering in a Notification Service Extension would keep one copy of
the text, but needs an extension target, an App Group and the language moved into shared
defaults. That is the way out if the two copies drift.

## Consequences

- The sentences and the currency table exist twice, in `PushCopy` and in the iOS catalog and
  `Currency`. A test renders every sentence in every language.
- No sentence uses a gendered word for a person. French avoids "vous" with an agreeing past
  participle.
- Reminders are limited to one a day per creditor, debtor and group, held in memory. A
  restart forgets them, and a second API instance would double the limit.
- The API needs `Apns__*` outside Development and refuses to boot without them.
- Push tokens and the app language now reach the server, so the privacy manifest, the App
  Store answers and the four privacy policies change with the client that sends them.
