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
| `Splitty.Infrastructure` | `ApplicationDbContext`, migrations, `PasswordHasher` |
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

Entities use `[Table("Name")]` (singular, PascalCase — so do the Postgres tables),
`[DatabaseGenerated(Identity)]` int keys, and `[JsonIgnore]` on back-references to stop
serialization cycles. `User.Password` is `[JsonIgnore]` — entities are returned directly
from some endpoints, so anything secret needs that attribute.

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

JWT bearer, HMAC-SHA256, 7-day expiry, issued by `AuthService.GenerateJwtToken`.

Claims: `NameIdentifier` = user id, `Name` = display name, `Email`, `Sub` = email.

**Use `ClaimTypes.NameIdentifier` for identity.** `Name` is the display name and is not
unique. Controllers read it as:

```csharp
var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
if (userId is null) return Unauthorized();
```

Passwords are Argon2 via `Isopoh.Cryptography.Argon2` (`PasswordHasher`). Controllers are
`[Authorize]` at class level; anonymous endpoints must opt out explicitly.

## Errors

Two coexisting styles:

- **Return `ActionResult` directly** for expected outcomes — `BadRequest`, `Unauthorized`,
  `Forbid`, `NotFound`, `Conflict`. Preferred for new code; the status code is explicit.
- **Throw and let middleware map it.** `GlobalExceptionHandlingMiddleware` maps
  `InvalidOperationException` → 400, `ArgumentException` → 400, `UnauthorizedAccessException`
  → 403, everything else → 500, all as `ErrorResponse`.

Enums serialize as snake_case strings (`JsonStringEnumConverter` in `Program.cs`).

## iOS client

SwiftUI, `Views/` + `ViewModels/` + `Components/`, no third-party dependencies.

- `APIClient` — singleton, one generic `request<T: Codable>` method, attaches
  `Bearer` token, posts `.unauthorizedError` on 401.
- `TokenManager` — Keychain storage (`kSecClassGenericPassword`, service
  `com.splitty.app`).
- `Services/*Service.swift` — thin wrappers over `APIClient`, async/await with legacy
  completion-handler variants kept for older call sites.

`APIClient.baseURL` is hardcoded to `http://127.0.0.1:8080`, and `Info.plist` sets
`NSAllowsArbitraryLoads` to permit cleartext. Both are local-dev shortcuts that need
replacing before any real deployment.

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

- **Secrets are committed.** `appsettings.json` contains the JWT signing key
  (`SplittySuperReallySecureSecretKey`) and the database password in plaintext.
- **`APIClient.swift` calls `DELETE /group/{id}`**, which no controller implements — 405s.
- **`GenerateJwtToken` uses `DateTime.Now`** for `expires`; it's interpreted as UTC, so
  token lifetime is shifted by the host's UTC offset.

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
