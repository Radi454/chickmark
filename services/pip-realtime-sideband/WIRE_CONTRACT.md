# Sideband wire contract

The control socket between the Flutter client and this service. **The server owns this
format.** Every field is `snake_case`, matching the rest of the backend (Supabase columns,
the `pip-realtime-session` payloads), and the server is the security boundary — the client
conforms to it, never the reverse.

Endpoint: `wss://<service>/v1/realtime`.

Implemented by:

- server — `src/binding.ts` (`parseBindFrame`), `src/sideband.ts` (`ClientNotice`),
  `src/server.ts` (close codes)
- client — `lib/services/realtime/realtime_sideband_channel.dart`

Pinned by a shared literal in `test/binding_test.ts` and
`test/services/realtime/realtime_sideband_channel_test.dart`. The two tests assert the
same bind frame character for character, so a change to one side fails the other side's
suite.

## Ordering rule

The **first application frame must be the bind frame**. Nothing else is accepted before
it: no health frame, no `bye`, and on the server side no control action, no lease claim
and no provider traffic happen until binding succeeds. A first frame that is not a valid
bind frame closes the socket with `4400`.

Credentials travel in that frame and **never in the URL** — a query string is written to
proxy logs, browser history and Cloud Run request logs. Neither token is ever logged,
echoed or stored by either side.


## Endpoint

The control plane (`pip-realtime-session start`) returns `sidebandUrl` as the
service's **base** url, with no path — it doubles as the Cloud Run OIDC
audience, which must not carry one.

The client derives the socket url from it:

    https://<service>.run.app  ->  wss://<service>.run.app/v1/realtime

The server upgrades **only** on `/v1/realtime`. Connecting to the base url
verbatim fails twice over: the path does not upgrade, and `https` is not a
valid WebSocket scheme. Dart-side helper: `sidebandWebSocketUri` in
`lib/services/realtime/realtime_sideband_channel.dart`, pinned by tests on both
sides.

Other routes on the same service: `GET /healthz`, and
`POST /internal/cleanup` (Cloud Scheduler, OIDC only).

## Inbound (client → server)

### `bind` — first frame, exactly once

```json
{
  "type": "bind",
  "session_id": "sess_1",
  "generation": 1,
  "access_token": "<supabase access token>",
  "binding_token": "<one-shot token from `pip-realtime-session start`>"
}
```

- `access_token` — the caller's Supabase JWT. Proves identity only; the server re-resolves
  authorization from the database.
- `binding_token` — single-use. A replay is rejected.
- `generation` — integer ≥ 1, the server-assigned attempt number from `start`.
- All four fields are required and must be non-empty strings (`generation` an integer).
  Anything else is not a bind frame.

### After binding

```json
{"type":"health","webrtc":true,"data_channel":true}
{"type":"bye"}
```

`health` reports the client's transport legs; READY is gated on both being true. Unknown
control frames are ignored rather than fatal.

## Outbound (server → client)

```json
{"type":"ready","session_id":"sess_1","generation":1}
{"type":"error","code":"identity_mismatch"}
{"type":"closing","reason":"server_drain"}
```

- `ready` — the authoritative go-ahead, sent at most once per connection. It is the only
  thing that may start audio transmission. The client checks `session_id` and `generation`
  against the current attempt, so a late READY from an abandoned attempt is inert.
- `error` — a machine code, never display text. The client maps it to a message; codes are
  the server's `BindFailure` values (`invalid_token`, `unknown_session`,
  `session_not_bindable`, `identity_mismatch`, `unauthorized`, `binding_token_rejected`,
  `kill_switch`, `malformed_frame`) plus the connection-level reasons
  `bind_frame_required`, `lease_unavailable`, `fence_lost` and `call_not_registered`. An
  `error` is always followed by a close.
- `closing` — advance warning that the socket is going away (drain). The close code that
  follows is what the client acts on.

Unknown event types must be dropped silently on both sides, so either can add a notice
without breaking the other.

## Captions do NOT flow over this socket

Transcript deltas reach Flutter over its **own WebRTC data channel, directly from
OpenAI**. The sideband is not in that path: it accumulates transcripts only to persist
finalized turns server-side, and it never sends a caption, a transcript or a turn-state
frame to the client. A client must not expect one.

## Close codes

Private range, so the client can tell the causes apart:

| Code   | Meaning                                                                            |
| ------ | ---------------------------------------------------------------------------------- |
| `4400` | malformed frame (including a bad or missing bind)                                  |
| `4401` | bind rejected — identity, authorization or token                                   |
| `4408` | bind timeout — no successful bind within `PIP_REALTIME_BIND_DEADLINE_SECONDS` (5s) |
| `4409` | lease lost — could not claim, or the fence moved                                   |
| `4500` | internal server failure                                                            |
| `4503` | draining — this instance is shutting down                                          |

Anything else (including `1000`) is a normal close and means the call ended.

The bind deadline starts when the socket is upgraded and is cleared the moment a bind
succeeds, so it can never close a healthy session. Before it fires the client is sent
`{"type":"error","code":"bind_timeout"}`, then the socket closes with `4408`. It exists
because an upgraded socket holds a Cloud Run concurrency slot for its whole life, and this
service runs with held WebSockets and a small max-instance count — an idle,
unauthenticated socket is an availability cost. Nothing durable has been claimed at that
point (no lease, no generation), so the close is purely local.
