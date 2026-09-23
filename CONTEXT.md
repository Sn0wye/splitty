# Splitty — Codebase Context

Shared-expense tracker: groups of people log expenses, split them, and settle up.
Same problem space as Splitwise.

Two deliverables in one repo:

| Path | What |
|---|---|
| `Splitty-API/` | .NET 9 REST API, PostgreSQL, layered solution |
| `Splitty/` | SwiftUI iOS client |
| `docker-compose.yml` | Postgres + API, both on the `postgres_network` bridge |

## Backend layout

`Splitty.sln` is layered, one project per responsibility. Dependencies point inward:

```
API ──> Service ──> Repository ──> Infrastructure (DbContext)
 │         │             │
 └─────────┴─────────────┴──────> Domain (entities), DTO
```

| Project | Contains |
|---|---|
| `Splitty.API` | Controllers, `Program.cs` wiring, middleware |
| `Splitty.Service` | Business rules, authorization decisions |
| `Splitty.Repository` | EF Core queries, one repository per aggregate |
| `Splitty.Infrastructure` | `ApplicationDbContext`, migrations |
| `Splitty.Domain` | Entities only, no behavior |
| `Splitty.DTO` | `Request/`, `Response/`, `Internal/` |
| `Splitty.Background` | `TransactionBackgroundService` — balance recomputation |
| `Splitty.Seeder` | `DatabaseSeeder` and `SeedCommand`, run via `dotnet run seed` |

Everything is registered scoped in `Program.cs`, interface-first. Services and
repositories use **primary constructors** for injection — match that style.

## Domain model

`User`, `Group`, `GroupMembership`, `Expense`, `ExpenseSplit`, `Balance`.

- A `Group` has many `GroupMembership` rows. Membership is the *only* access control in
  the system — see below.
- An `Expense` has one payer (`PaidBy`) and many `ExpenseSplit` rows, one per participant.
- `ExpenseType` is `Expense` or `Payment`; settlements are recorded as `Payment`.
- `Balance` is a **pairwise, per-group** row: `(UserId, PeerId, GroupId, Amount)`. Each
  debt is stored twice, once from each side, with opposite signs. These rows are internal
  bookkeeping; clients receive simplified debts.

**Split mode** is `Expense.SplitMode` — `equal`, `custom`, or `percentage` — stored on the
row so reopening an expense recovers how it was divided instead of inferring it from the
amounts. It is **descriptive, not authoritative**: nothing server-side derives an amount
from it, so a percentage expense whose shares do not divide evenly is still accepted and
the client keeps ownership of where the remainder cent lands. Per-split shares live in
`ExpenseSplit.Percentage`, in percent units, non-null on every row of a `percentage`
expense and null everywhere else — percentages sent under any other mode are nulled on
write rather than refused. The column is nullable because a settlement has no mode; the
service is what keeps it non-null for every `Type = Expense` row. Splits and mode are one
fact, so an update sending `Splits` must send `SplitMode` too.

**Category** is `Expense.Category` — one value from a closed, server-defined list, stored as
text, `NOT NULL`, defaulting to `general`. It is descriptive: no amount, balance, or invariant
reads it. A settlement holds `payment`, a value no expense may take and the picker never
offers, so every row has a category and the client derives its glyph and tint from that alone.
The expense routes refuse `payment` with a `400`; the settlement routes coerce whatever they
are sent to `payment`. Adding a value is cheap, renaming one is a data migration. See
`docs/adr/0002-expense-categories-are-a-closed-text-list.md`.

**Expense date** is `Expense.Date`, nullable, client-supplied, and may be in the future.
`CreatedAt` next to it is the audit timestamp — server-set, never accepted from a client.
Rows predating the column have no `Date`, so every reader that orders or groups expenses uses
`Date ?? CreatedAt`, newest first. Expense and settlement creation both accept a date. On an
update, an omitted or null date leaves the stored date unchanged.

**Settlements are mutated through `/group/{groupId}/settlements/{expenseId}`**, never through
the expense routes, even though a settlement is an `Expense` row. The expense `PUT`/`DELETE`
refuse `Payment` rows rather than branching on `Type`. The settlement edit rebuilds both
splits from the new amount and re-applies the cap of invariant 5 with the settlement's *own*
contribution excluded — the stored balance already counts it, so a cap read raw would reject
even re-saving the amount already there. See
`docs/adr/0001-settlements-have-their-own-routes.md`.

Deletion is immediate and permanent, with no history or restore. Any member may delete any
expense or settlement, just as any member may edit one. If a settlement has already paid
against an expense, deleting that expense deliberately leaves the payment in place and
reverses the debt so the group can settle it in the other direction.

**Settle direction** is always caller-as-debtor. `POST /settle` records *the caller* paying
the peer, so "who can settle a debt" has exactly one answer: the person who owes it. There is
no route for recording that someone paid *you*, and no counterparty confirmation.

Entities use `[Table("Name")]` (singular, PascalCase — so do the Postgres tables),
`[DatabaseGenerated(Identity)]` int keys, and `[JsonIgnore]` on back-references to stop
serialization cycles. Entities are returned directly from some endpoints, so anything
that must not reach a client needs `[JsonIgnore]`.

### Invariants

These are the rules the domain actually depends on:

1. **Group balances sum to zero.** Every expense creates equal and opposite `Balance`
   rows. Anything that removes a participant with a nonzero balance breaks this and
   silently loses money — which is why member removal is gated on a zero balance.
2. **Membership is the authorization boundary.** There are no roles. `Group.CreatedBy`
   records who created the group and grants nothing. Every group member can do everything
   — edit others' expenses, settle, invite, remove settled members. This is deliberate,
   and matches Splitwise's stated position that anyone involved should be able to correct
   mistakes.
3. **Every group sub-resource checks membership.** Controller actions under
   `/group/{groupId}/...` call `groupService.IsMemberAsync(...)` and return `Forbid()`.
   Adding an endpoint without that check is the failure mode to watch for.
4. **The balance replay has exactly one caller: the background worker.** Nothing in the
   code enforces this — no visibility modifier, no analyzer, no constraint. It is what makes
   duplicate pairwise rows impossible without a unique index on `(UserId, PeerId, GroupId)`,
   so a second call site reintroduces the duplicates silently. A test pins the caller list;
   this entry is why it exists. Request a recomputation, never perform one.
5. **Settlements are capped at the smaller of the payer's net debt and the payee's net credit
   in that group.** Both positions come from stored pairwise balances, not from the suggested
   pairs. Members can pay a net creditor without having shared an expense. Editing excludes
   the payment's own contribution from both positions. Pending groups cap at zero; the
   eventually consistent cap can produce a retryable `400`.

## Language

Terms that mean something specific here, and the words to avoid for them.

**Simplified debt**:
A directed amount from one debtor to one creditor within a group. Greedy matching of the
largest net debtor and creditor, with user-id tie breaks, produces at most members minus one
payments. This is the only debt representation clients receive; it is deterministic, but
is not guaranteed to use the mathematical minimum number of payments. A settled group has
no simplified debts. See `docs/adr/0003-debts-are-simplified.md`.

**Settlement**:
A repayment recorded between two members, stored as an `Expense` with `Type = Payment`.
The code and API call it a settlement; on screen it is always a **payment**.
_Avoid_: refund, transfer, payback

**Participant**:
A member carrying a split row on an expense. Distinct from the payer, who need not be one.
_Avoid_: member (when talking about a single expense)

**Split mode**:
How the per-user amounts were derived: *equal*, *custom*, or *percentage*. Stored on the
expense, so reopening one recovers it rather than inferring it.
_Avoid_: split type, division method

**Custom split**:
Per-person amounts typed by hand, which must sum exactly to the total.
_Avoid_: exact split, manual mode

**Category**:
What an expense was for, chosen by the user from a fixed list. Leaves are grouped under
headings (Food and drink, Transportation, …) for display only; the heading is never stored.
`general` means nobody chose. `payment` is the category every settlement carries.
_Avoid_: tag, label, type (`ExpenseType` already owns "type")

**Peer**:
A member of a group you are also in, seen from your side. Already the domain word — it is
the `Balance.PeerId` column. The code and API say peer; the screen listing them is called
**People**, the same code-versus-screen split as settlement versus payment.
_Avoid_: friend, contact, counterparty

## Balance recomputation

Balances are **derived state, recomputed wholesale** — never incrementally patched.

`BalanceService.CalculateGroupBalances` zeroes every balance for the group, replays all
expenses and splits, and writes the result back. It's idempotent by construction.

It runs asynchronously. Money writes request a recomputation instead of performing one, and
the request belongs to the write itself: `ExpenseService` (create, update, delete) and
`BalanceService` (settle, edit and delete a settlement) enqueue after each successful save,
so a controller or any other caller cannot persist money and forget the recomputation. A
rejected write enqueues nothing. The summary-refresh route is the only controller call left:

```csharp
await balanceRecomputeQueue.EnqueueAsync(groupId);
```

`IBalanceRecomputeQueue` is the only supported way to ask for a recomputation — it marks
the group pending and then writes to the channel, in that order, since queueing first lets
the worker clear a flag the caller has not set yet. `Channel<TransactionRequest>` is an
unbounded singleton with `SingleReader = true`; `TransactionBackgroundService` drains it,
resolving a fresh scope per message.

So **balances are eventually consistent** — right after creating an expense, a read may
still return pre-expense numbers. The client must not assume a write is immediately
reflected. A group's net balance is the sum of the signed-in member's pairwise `Balance`
rows; the overall figure on the groups list is the sum of those group nets.

`Group.BalancesPending`, surfaced as `balancesPending` on the summary response, says a
recomputation is outstanding, including simplified debts. The summary serves the whole
group's stored simplified debts, and People uses those same per-group amounts. Pending
figures may be stale and settlement creation or editing is refused until recomputation.
The flag is eventually consistent, not a lock or transaction barrier.

## Auth

Sign-in is OAuth only. There is no password anywhere in the system: no `User.Password`
column, no hasher, no `/auth/register` and no `/auth/login`.

```
iOS gets result.serverAuthCode from the Google Sign-In SDK
  → POST /oauth/google { authCode }
API exchanges it at oauth2.googleapis.com/token with the *Web* client id + secret
  → validates the returned id_token
  → upserts User + OAuthAccount
  → 200 { token, user }
```

The app never holds the client secret and never sees a Google access or refresh token —
only a one-time code, then a Splitty JWT. `IGoogleTokenExchanger` is the only component
that talks to Google over the network, which is what makes `OAuthService` testable.

`OAuthAccount` holds one provider identity: `(Provider, Subject)` unique, plus the email
**as the provider sent it**, denormalized so linking bugs are answerable. `User.Email`
stays canonical. `Subject` is the identity, not the email.

**Linking rule.** An unseen subject whose email matches an existing user links to that
user *only when the provider reports `email_verified`*. An unverified match is rejected
outright — it is an account-takeover path, not a nicety. (`User.Email` is uniquely
indexed, so an unverified collision cannot fall back to a second user either.)

`Name` and `AvatarUrl` come from the Google payload **once, at user creation**. They are
never overwritten on later sign-ins, or an in-app rename would silently revert. `Name` is
editable through `PATCH /profile`; `AvatarUrl` is provider-owned and is not.

## Profiles and avatars

`/profile` is the one resource for reading and editing a user. There is no `GET /auth`.

```
GET   /profile                    the signed-in user
PATCH /profile                    partial update: name, avatarKey
GET   /profile/{userId}           a peer — 404 unless a group is shared
POST  /profile/avatar/upload-url  a presigned PUT slot
```

All four return or accept `ProfileResponse`, a DTO rather than the `User` entity, so
adding a column is not automatically an API change. The peer read is gated on **sharing a
group** and 404s otherwise — membership is the only authorization boundary in the system,
and a 403 would confirm the account exists.

`PATCH` is partial by construction. `Patch<T>` (`Splitty.DTO/Json`) distinguishes an
absent property from an explicit `null`; a plain nullable would collapse the two and make
every omitted field a clear. An explicit `"avatarKey": null` removes the uploaded image.
Names are trimmed, non-empty, capped at 60 characters, and **not unique**.

**Avatar resolution**, in order: the uploaded object → the provider's `AvatarUrl` when
non-empty → a generated DiceBear URL. The client is never told which one it got.

Two columns carry this. `AvatarUrl` still holds the provider's picture, written once.
`AvatarKey` holds the **key** of the uploaded object, not an absolute URL, so the storage
host can move without rewriting rows. **The generated default is computed, never stored** —
a stored default is a stored default forever, so the rows that predate avatars fix
themselves and a later move off DiceBear needs no backfill. Seeded on the **user id**,
never the email: the seed is rendered verbatim in every peer's client. The hosted DiceBear
API routes on the major version only (`11.x`; `11.0` is a 404), so an exact minor cannot
be pinned.

**Upload flow.** The client asks for a URL, PUTs the image straight to R2, then sends the
key back. The bytes never pass through the API, so there is no request-size configuration
or streaming code here. On commit the API confirms the object exists, is under 2 MB and is
`image/jpeg`, and that the key carries the caller's own `avatars/{userId}/` prefix —
without that last check a user could point their row at someone else's object. The
previous object is then deleted **best effort**: a failed delete is logged, not fatal.
Keys contain a fresh UUID, so a committed URL is permanently cacheable.

`IAvatarStorage` is the only component that talks to Cloudflare, the way
`IGoogleTokenExchanger` is the only one that talks to Google — that is what keeps
`ProfileService` testable. It is implemented with `AWSSDK.S3` against R2's S3-compatible
endpoint; hand-rolling SigV4 reimplements a solved problem. Size and type are enforced on
commit rather than in the signature because an S3 presigned PUT cannot bound a body whose
length is unknown at signing time.

`POST /auth/dev-login { email }` mints a token for a seeded user with no credential. It
exists only when the host is Development — `Program.cs` strips `DevAuthController` from
the application model otherwise, so the route 404s rather than 401s.

JWT bearer, HMAC-SHA256, issued by `JwtTokenIssuer.Issue`. Expiry is `Jwt:ExpiryDays`,
default 30. Refresh tokens are out of scope.

Claims: `NameIdentifier` = user id, `Name` = display name, `Email`, `Sub` = email.

**Use `ClaimTypes.NameIdentifier` for identity.** `Name` is the display name and is not
unique. Controllers read it as:

```csharp
var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
if (userId is null) return Unauthorized();
```

Controllers are `[Authorize]` at class level; anonymous endpoints must opt out explicitly.

### Secrets

`Jwt__SecretKey`, `Google__ClientId`, `Google__ClientSecret` and the five `R2__*` keys
(`AccountId`, `AccessKeyId`, `SecretAccessKey`, `BucketName`, `PublicBaseUrl`) come from `Splitty-API/.env`
(gitignored; `.env.example` is the template). ASP.NET maps the double underscore to a
config section. `appsettings.json` keeps `""` placeholders and is a schema, not a config.
`Program.cs` throws at startup if any of them is empty outside Development.

`R2__PublicBaseUrl` is the host that **serves** the images — a custom domain bound to the
bucket. It is not the `<AccountId>.r2.cloudflarestorage.com` S3 API endpoint, which the
SDK signs against and which is not publicly readable, and not the `r2.dev` subdomain,
which Cloudflare rate-limits and documents as unsuitable for production.

Compose passes the file through `env_file:`. Running the API directly:

```bash
set -a; source Splitty-API/.env; set +a
dotnet run --project Splitty-API/Splitty.API
```

The connection string stays in `appsettings.json` — `splitty/splitty` against a local
container is not a secret.

## Errors

Two coexisting styles:

- **Return `ActionResult` directly** for expected outcomes — `BadRequest`, `Unauthorized`,
  `Forbid`, `NotFound`, `Conflict`. Preferred for new code; the status code is explicit.
- **Throw and let middleware map it.** `GlobalExceptionHandlingMiddleware` maps
  `InvalidOperationException` → 400, `ArgumentException` → 400, `KeyNotFoundException`
  → 404, `UnauthorizedAccessException` → 403, everything else → 500, all as `ErrorResponse`.

Enums serialize as snake_case strings (`JsonStringEnumConverter` in `Program.cs`).

## iOS client

SwiftUI, `Views/` + `ViewModels/` + `Components/`, no third-party dependencies.

- `APIClient` — singleton, one generic `request<T: Codable>` method, attaches
  `Bearer` token, posts `.unauthorizedError` on 401.
- `TokenManager` — Keychain storage (`kSecClassGenericPassword`, service
  `com.splitty.app`).
- `Services/*Service.swift` — thin wrappers over `APIClient`, async/await only. There are
  no completion-handler variants; views call the async methods from `.task` / `Task`. New
  endpoints go in a service and call `APIClient.request` directly rather than adding another
  pass-through method to the client.
- `AuthenticationManager.currentUser` is the signed-in `User`: set from the sign-in response,
  and fetched once on a cold launch that restored a Keychain token. Everything that says
  "you" reads it. Not cached in UserDefaults — a second copy of the profile can go stale, a
  Keychain token cannot. The profile route is `GET /profile`.

**Money is integer cents everywhere on the client**, converted to `Double` once at the
request boundary (`Money`). The API validates that splits sum *exactly* to the total against
a `decimal` column, so deriving them in floating point makes that a coin flip. The expense
sheet is built from three pieces: `AmountExpression` (the amount field's state machine, with
chained left-to-right arithmetic and no precedence), `SplitConfiguration` (payer plus an
equal, custom or percentage mode, and the only place remainder cents are distributed — to
the lowest user ids), and `ExpenseFormViewModel`, which holds the two together and decides
when Save is available. A member who would land on zero is *omitted* from the payload, never
sent as `0`.

Equal and percentage splits **derive their amounts from the total on demand**, so moving the
total re-divides them; a custom split keeps the typed amounts and reports the shortfall
instead. `SplitConfiguration(restoredFrom:)` reads the stored mode; `init(inferredFrom:)`
is the fallback for a row that has none — a settlement, a row older than the column, or a
mode this build does not recognise, which decodes as `nil` rather than throwing.

The split screen is a payer row, a mode selector and the member list — **there are no
presets**: with the mode on screen, a preset row that only moves that selector is a second
control for one action. Each mode keeps its own draft (checkbox set, typed amounts, typed
percentages) on `ExpenseFormViewModel` for as long as the *sheet* is open, since the split
screen itself is popped and pushed constantly while composing. A blank amount or percentage
field means "not participating"; the percentage fields use the system `.decimalPad`, not the
calculator pad, which exists for totals summed off a receipt.

The amount field is a real `UITextField` whose `inputView` is the SwiftUI calculator pad
(`AmountInputField`), not a `.decimalPad` with an accessory bar: a real responder is what
gives the field a caret and makes moving focus to the description swap the pad for the system
keyboard. The description field's `inputAccessoryView` carries the expense date picker.

**The API base URL comes from the build configuration, not a literal.** The
`SPLITTY_API_BASE_URL` build setting is substituted into the `SplittyAPIBaseURL` key of
`Info.plist`; `APIConfiguration` validates it (http/https, host present, trailing slash
stripped) and `APIClient` resolves it once at init, then rethrows on every request. Debug points at
`http://localhost:8080`. **Release is deliberately empty**, so a Release build throws
`APIError.missingBaseURL` on the first request rather than silently talking to a
developer's machine — set the setting when there is a real host to point at.

Cleartext is permitted only through an `NSExceptionDomains` entry for `localhost` — ATS
matches domain names, not IP literals, so point the base URL at `localhost` rather than
`127.0.0.1`. There is no `NSAllowsArbitraryLoads`, so a Release build cannot reach an
arbitrary cleartext host.

There is no client method for deleting a group, and no route to call: a group is destroyed
when its last member leaves (`POST /group/{groupId}/leave`).

## Local development

```bash
docker compose up -d                      # Postgres :5432, API :8080
dotnet run --project Splitty-API/Splitty.API
dotnet run --project Splitty-API/Splitty.API seed   # reset, seed, wait for balances, exit
dotnet ef migrations add <Name> --project Splitty-API/Splitty.Infrastructure
```

API listens on `0.0.0.0:8080` (Kestrel config in `appsettings.json`). In Development,
OpenAPI is at `/openapi/v1.json` with Scalar UI at `/scalar`.

### Seeding

The seed command **starts the host** rather than seeding and returning: balances are
written by a hosted service, so a process that enqueued and exited would leave every group
`balancesPending` with no worker to clear it. It seeds, requests one recomputation per
group through `IBalanceRecomputeQueue`, waits until no seeded group is pending, stops the
host, and exits non-zero if that wait times out. The seeder never calls
`CalculateGroupBalances` itself — invariant 4.

The data set is **fixed, not random**: six users, a six-member group with amounts from
$4.20 to $1,240, a two-member group, one group where `john@example.com` owes and one where
he is owed, a pair settled to exactly zero, and a `Payment` row. `SeedData` holds it, and
`DatabaseSeeder.Validate` rejects a row the API would have refused from a client.

Re-running is safe because the command **clears the tables it owns first** — every
`User`, `Group`, `Expense`, `ExpenseSplit`, `GroupMembership`, `Invite`, `OAuthAccount` and
`Balance` row. It is a local development reset, not an upsert: anything created by hand in
the dev database goes with it.

## Known issues

Live problems, not style preferences:

- **The database password is committed.** `appsettings.json` carries the connection
  string in plaintext. Deliberate for the local container; it needs to move before any
  deployment that isn't localhost.

## Invites

`POST /group/{id}/join` is gone. Joining a group requires redeeming an invite code:

```
POST /group/{groupId}/invites             create   (member only)
POST /invite/{code}/accept                redeem   (any authed user, rate limited)
POST /group/{groupId}/leave               self-leave        (net balance must be 0)
DELETE /group/{groupId}/members/{userId}  remove member     (net balance must be 0)
```

- Codes are 6 chars of `A-Z0-9`, stored raw (they must be displayable), unique.
- `ExpiresAt` defaults to 7 days out; a client-requested value is capped at 30 days.
- `MaxUses` null means unlimited. Redemption claims a use with a conditional
  `UPDATE ... WHERE MaxUses IS NULL OR UsedCount < MaxUses`; zero rows affected means
  exhausted. No row locks, no read-then-write race.
- The redeem route takes no `groupId` — the group is derived from the code alone. Two
  sources of truth for the same fact is how the original hole appeared.
- Redemption is guessing-resistant by rate limit, not by code entropy: 10/min per
  `ClaimTypes.NameIdentifier`, `QueueLimit = 0`, 429 on reject. `UseRateLimiter()` must
  stay after `UseAuthentication()` or the partition key is null.
- Removing the last member hard-deletes the group; existing cascades handle children.
- A departed member's `Expense` and `ExpenseSplit` rows are retained and still reference
  them, so `MemberDTO` falls back to `[removed]` for a user with no membership row.

Design and full decision record in issue #2. Deferred to phase 2: web/deep links,
iOS client support, invite list + revoke.
