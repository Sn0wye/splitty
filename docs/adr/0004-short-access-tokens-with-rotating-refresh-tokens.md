# Short access tokens with rotating refresh tokens

Sign-in returns two credentials. The **access token** is the Splitty JWT, unchanged in
claims and signing, but valid for `Jwt:AccessTokenMinutes` (15) instead of 30 days. The
**refresh token** is 32 random bytes, base64url-encoded, opaque, and stored only as a
SHA-256 hash in the `RefreshToken` table. `POST /auth/refresh` trades it for a new access
token and a new refresh token; `POST /auth/logout` revokes it.

Each refresh revokes the presented row and inserts its replacement with
`ExpiresAt = now + Jwt:RefreshTokenDays` (90). The window slides, so a user who opens the
app at least once every 90 days never signs in again, and an abandoned device's credential
dies on its own. Every row belongs to a **family**, one sign-in on one device. Two devices
are two families, so signing out on one leaves the other alone.

JWT validation's clock skew drops from the 5-minute default to 30 seconds. At 5 minutes a
15-minute token would really last 20.

## Rejected: one longer JWT

Raising the old `Jwt:ExpiryDays` (30) only moves the date when users are thrown out. It
also lengthens the worst case for a leaked token. A JWT cannot be revoked, so signing out
on a device would leave its token working until it expired.

## Rejected: reissuing the JWT on a sliding basis

The server could hand back a fresh JWT on every request, or on a `/refresh` that accepts
the current one, with no server-side state. That keeps users signed in, but a stolen token
can then be renewed forever, and nothing can revoke it, logout included. Revocation needs a
row the server can mark. Once that row exists, the long-lived credential should be the one
behind it, and the stateless JWT should be short.

## Reuse detection

A refresh token works once. If a row that is already revoked comes back, either the client
or someone holding a copy is replaying it, and the server cannot tell which. It revokes
every live row in the family and returns 401. Whoever was holding the newest token, the
user or an attacker, has to sign in again. That lockout is the point: a stolen refresh token
stops working as soon as both parties have used it.

Revocation is a conditional update (`WHERE "RevokedAt" IS NULL`) in the same transaction
that inserts the replacement. When two requests present the same token at once, one claims
the row and the other matches nothing, takes the reuse path, and revokes the family,
including the winner's new token. The iOS client sends one refresh at a time, so a real race
means something is wrong. Treating it as reuse costs a well-behaved client nothing, and
letting both requests through would give a stolen copy an easy way past detection.

## The 401 is generic

Unknown, expired, revoked and reused tokens all get the same 401 and message, and logout
answers 204 for any token. A different answer would tell an attacker which tokens once
existed.

## Not covered

There is no absolute lifetime for a family beyond the sliding window, no purge of expired
or revoked rows, no list of active sign-ins, and no rate limit on `/auth/refresh`. Tokens
issued before this change were not upgraded, because the app had no real users yet.
