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
| `Splitty.Seeder` | `DatabaseSeeder`, run via `dotnet run seed` |

Everything is registered scoped in `Program.cs`, interface-first. Services and
repositories use **primary constructors** for injection — match that style.

## Domain model

`User`, `Group`, `GroupMembership`, `Expense`, `ExpenseSplit`, `Balance`.

- A `Group` has many `GroupMembership` rows. Membership is the *only* access control in
  the system — see below.
- An `Expense` has one payer (`PaidBy`) and many `ExpenseSplit` rows, one per participant.
- `ExpenseType` is `Expense` or `Payment`; settlements are recorded as `Payment`.
- `Balance` is a **pairwise, per-group** row: `(UserId, PeerId, GroupId, Amount)`. Each
  debt is stored twice, once from each side, with opposite signs.

**Split mode** — "equal", "exact", "percentage" — is a **client-only** concept. The API
accepts and stores absolute per-user amounts and nothing else, so a mode exists only for as
long as it takes the client to turn it into numbers. Reopening an expense cannot recover how
it was originally split, and searching the backend for the term finds nothing by design.

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
5. **Settlements are capped at what the caller currently owes the peer.** Recording a
   settlement stays unilateral — one member, one request, no counterparty confirmation — but
   it cannot exceed the debt. The cap reads the eventually-consistent balance table rather
   than a live aggregate, which is deliberate: an over-tight cap is a retryable `400`, not a
   wrong number. The consequence is that a group whose balances the worker has not written
   yet caps at zero and rejects every settlement.

## Balance recomputation

Balances are **derived state, recomputed wholesale** — never incrementally patched.

`BalanceService.CalculateGroupBalances` zeroes every balance for the group, replays all
expenses and splits, and writes the result back. It's idempotent by construction.

It runs asynchronously. Controllers that mutate money enqueue instead of recomputing
inline:

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
reflected.

`Group.BalancesPending`, surfaced as `balancesPending` on the summary response, says a
recomputation is outstanding. It is a **display hint only**: it exists so a client can show
a spinner instead of presenting stale numbers as final. Nothing branches on it for
correctness, and nothing should — it is written and cleared by the queue and the worker, so
treating it as a lock or a read barrier would be trusting a flag that is itself eventually
consistent.

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
never overwritten on later sign-ins, or an in-app rename would silently revert.

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

`Jwt__SecretKey`, `Google__ClientId` and `Google__ClientSecret` come from `Splitty-API/.env`
(gitignored; `.env.example` is the template). ASP.NET maps the double underscore to a
config section. `appsettings.json` keeps `""` placeholders and is a schema, not a config.
`Program.cs` throws at startup if any of the three is empty outside Development.

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
  no completion-handler variants; views call the async methods from `.task` / `Task`.

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
dotnet run --project Splitty-API/Splitty.API seed   # seed, then exit
dotnet ef migrations add <Name> --project Splitty-API/Splitty.Infrastructure
```

API listens on `0.0.0.0:8080` (Kestrel config in `appsettings.json`). In Development,
OpenAPI is at `/openapi/v1.json` with Scalar UI at `/scalar`.

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
