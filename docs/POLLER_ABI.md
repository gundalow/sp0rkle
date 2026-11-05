# Poller lifecycle ABI

The poller manager keeps caller-owned poller registrations and connection
state. It deliberately does not create threads or timers: the application
scheduler drives periodic work by calling `bot_poller_set_poll_all` when
pollers are due. This separates deterministic lifecycle semantics from the
event-loop/scheduler implementation.

## Structures

`struct bot_poller_entry` is 40 bytes:

| Offset | Field | Type |
|---:|---|---|
| 0 | start callback | `void (*)(void *ctx)` |
| 8 | stop callback | `void (*)(void *ctx)` |
| 16 | poll callback | `void (*)(void *ctx, void *const *contexts, size_t count)` |
| 24 | opaque context | pointer |
| 32 | active | uint32 |
| 36 | registered | uint32 |

`struct bot_poller_state` is 24 bytes: connection count at offset 0,
entry-array pointer at 8, and entry count at 16.

## Operations

- `bot_poller_set_init(state, entries, count)` resets connection count and every entry's active and registered flags. Storage must remain valid for the state lifetime.
- `bot_poller_set_add(state, index)` registers/activates an entry. If at
  least one connection exists, its start callback runs immediately.
- `bot_poller_set_connection(state, connected)` increments/decrements the
  number of active IRC connections. All pollers start only on transition
  from zero to one; all stop only on transition from one to zero. Additional
  connection events do not duplicate starts/stops.
- `bot_poller_set_poll_all(state, contexts, count)` invokes each active
  poll callback in registration order and returns the number invoked.

Callbacks are synchronous and execute on the caller's thread. They must not
re-enter or mutate the same poller state. The caller serialises lifecycle and
poll calls, validates connection-count balance, and handles callback failures
within its own callback context (the ABI callbacks return void). Poller
intervals and scheduling deadlines are owned by the application scheduler.
