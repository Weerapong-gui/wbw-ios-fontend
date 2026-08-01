# SUS as the test backend

The app now points at **Student-Union-Server (SUS)** instead of the legacy Node backend.
SUS is the stack that will actually ship, so testing against it — rather than against Node —
is what makes a test run mean anything.

This file records how the setup works and what has to travel with any future change, so a
tweak made while testing does not get lost on the way to the real server.

- **Date:** 2026-08-02
- **App config:** `WBW/Config.swift`, `Config.backend = .susLocal`
- **SUS repo:** `/Users/park/Student-Union-Server`, branch `feat/wbw-chat`

## The four backends

`Backend` in `WBW/Config.swift` is the only switch. Changing `Config.backend` changes the
whole app at once.

| case | base URL | what it is |
|---|---|---|
| `.prodNode` | `https://wbw.sumfu.store` | legacy Node backend, still live |
| `.nodeLocal` | `http://localhost:4000` | the same Node code in a local docker stack |
| `.susLocal` | `http://localhost:8080/wbw` | **current default** — SUS in a local docker stack |
| `.susProd` | `https://api.studentunion.social/wbw` | deployed SUS, behind a named Cloudflare tunnel |

`mePath` differs by family: Node serves the profile at `/auth/me`, SUS at `/me`. That is
already handled per case; nothing else in the app needs to know which backend it is talking to.

`Info.plist` already carries `NSAppTransportSecurity → NSAllowsLocalNetworking`, so the two
`http://localhost` cases work from the simulator without further changes.

## Switching backends wipes your chat data — every time

**This is the trap.** `Config.backend` swaps the API base but leaves the SwiftData chat cache
and the `chat.cursor.*` / `chat.read.*` defaults untouched. Each backend numbers
`group_message.id` in its own space, so after a switch the app asks the new backend for
messages after an id it never issued. Every request returns `200` with an empty list — nothing
errors, nothing logs, and the chat simply looks frozen.

Seen for real on 2026-08-01 switching Node → SUS: the cache held ids 360-365 from Node testing
while SUS's highest id was 35, and the app long-polled `?after=365` forever.

**Whenever you change `Config.backend`, delete the app's data before running it again.** A
proper fix would key the cache by backend, or purge on a `Config.backend` mismatch at launch;
neither is implemented.

## Running SUS locally

```bash
cd /Users/park/Student-Union-Server
docker compose up -d          # su-server on 127.0.0.1:8080, postgres-db on 127.0.0.1:5432
```

Database is `sudb`, user `admin` (see `.env` — `DB_USER`, `DB_NAME`, `DB_PASS`). Inspect it with:

```bash
docker exec postgres-db psql -U admin -d sudb -c '\dt'
```

The WBW tables live in the same database as the rest of SUS: `app_user`,
`participant_profile`, `participant_group`, `group_message`, `group_chat_state`.

Note that SUS's Postgres publishes host port **5432**, and the Node stack's publishes **5433**
(via an untracked `backend/docker-compose.override.yml` in the WBW repo, added because SUS got
there first). Both can run side by side.

## Test accounts

| username | password | note |
|---|---|---|
| `6931900001` | *unknown* | pre-existing, in group 1 with ~40 messages of history |
| `6931900002` | *unknown* | pre-existing, in group 1 |
| `6931900011` | `chatv2test` | created 2026-08-02 for verification, group 2 |
| `6931900012` | `chatv2test` | created 2026-08-02 for verification, group 2 |

New participants can be registered through the API without touching the database — the student
id must be 10 digits starting `693`, and the password at least 8 characters:

```bash
curl -s -X POST http://localhost:8080/wbw/auth/register \
  -H 'content-type: application/json' \
  -d '{"student_id":"6931900013","password":"chatv2test",
       "profile":{"first_name":"Test","last_name":"Chat","school_id":1,
                  "contact_phone":"0810000000","emergency_contact_name":"EC",
                  "emergency_contact_phone":"0811111111"},
       "medical":{"birthdate":"2007-01-01","blood_type":"O"},
       "health":{"chronic_conditions":[]},
       "consent":{"consent_health_data":true,"consent_emergency_treatment":true,
                  "waiver_accepted":true}}'
```

## What was verified against SUS on 2026-08-02

All against the running local stack, group 2:

- **Join cut-off** — A sent two messages, B joined afterwards and its first sync returned
  **0 messages** with `since_id 56`, `member_count 2`, and one cursor (the caller is excluded).
  A then sent one more and B saw exactly that one.
- **Long-poll** — B parked on `?wait=15`, A sent a second later, and B's request returned in
  1.04 s total, so it woke roughly 40 ms after the send rather than riding out the wait.
- **Read receipts** — B posted `/chat/read`, and A's next sync showed B's cursor at the new id.

Then the app itself, reinstalled on the simulator to clear the Node-era cache and launched
straight into the chat as `6931900011`. One screen showed the whole feature working against
SUS at once: the header's member count, sent bubbles with tails and `02:17` times, the
`อ่านแล้ว 1 · ทั้งกลุ่ม` read-receipt line, the `ข้อความใหม่` divider, and an incoming message
from the other account arriving live with its avatar and sender name.

Every route the app needs is present in the running binary: `/chat/sync`, `/chat/read`,
`/groups/{id}/join`, `/groups/leave`, `/groups/{id}/members`, `/groups/members/index`,
`/messages` (both verbs), `/devices/register` and `/unregister`, `/staff/checkpoints` and
`/checkin`, `/notifications`, and `GET`/`PATCH /me`. An unknown path under `/wbw` returns 404,
so the 401s on those routes are real routing rather than a catch-all.

## Carrying changes to the real server

The local stack and the deployed one run the same code from the same repo, so anything changed
while testing has to reach production the same way any other change does — through the SUS
repo, not by editing a running container.

- **Code and route changes** live in `/Users/park/Student-Union-Server` on `feat/wbw-chat`.
  That branch is pushed and awaiting a PR; merge it rather than cherry-picking.
- **Schema changes** must be a migration in the SUS migrations directory, not an ad-hoc `psql`
  statement against `sudb`. The compose stack runs `migrate/migrate` against the same files, so
  a migration that works locally is the one that will run in production.
- **Configuration** — `.env` is per-environment and is not committed. A new variable has to be
  added to the deployed environment separately, or the deploy will start and then fail on first
  use. `TUNNEL_TOKEN` is what binds the deployment to `api.studentunion.social`.
- **`Config.backend` must go back to a shipping value before the app is released.** It is
  `.susLocal` right now, which points at a machine that will not exist for users.

Chat v2's own deployment checklist — the long-poll requirements around proxy buffering, file
descriptors, and Postgres connection limits — lives at `docs/chat-v2-deploy.md` in the SUS
repo. Read it before deploying, and note the connection-budget finding recorded there.

## Known gaps in this setup

- **Push has never actually fired.** There is no Firebase service account in the local
  environment, so the push path exits before contacting FCM. Payload shape, collapse behaviour,
  batching, and invalid-token cleanup are all unverified anywhere.
- **The passwords for `6931900001` / `6931900002` are not recorded here.** Those two accounts
  hold the only realistic chat history (about 40 messages in group 1); the accounts created for
  verification start from empty.
- **`api.studentunion.social` has not been exercised from the app.** `.susProd` now carries the
  real host instead of a placeholder, but nothing has pointed at it and confirmed a round trip.
