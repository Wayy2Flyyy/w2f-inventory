# Framework support

`w2f-inventory` runs on **Qbox (`qbx_core`)**, **QBCore (`qb-core`)** and **ESX
(`es_extended`)**. All framework-specific logic is isolated in a bridge layer:

- `server/framework.lua` – server bridge (player lookup, money, metadata,
  persistence, lifecycle events, admin gate, usable items).
- `client/framework.lua` – client bridge (money read/refresh, group updates).

Every other file talks only to the `Framework.*` API and a single QB-shaped
player facade, so no other file ever branches on the framework.

## Selecting the framework

Set the convar in `server.cfg` **before** the resource starts:

```cfg
# qbx (Qbox) | qb (QBCore) | esx (ESX) | auto (default)
setr inventory:framework auto
```

`auto` detects the framework from whichever core resource is `started`
(`qbx_core` → `qb-core` → `es_extended`, in that order). Set it explicitly if
your start order is unusual. Aliases accepted: `qbox`, `qbcore`/`qb-core`,
`es_extended`.

The core framework is **not** a hard `dependency` in `fxmanifest.lua` (so the
resource can boot on any of the three); make sure your framework still starts
before `w2f-inventory`.

## Persistence

Player inventories are stored as JSON on the framework's character table; the
column is created automatically on first start:

| Framework | Table     | Key          |
|-----------|-----------|--------------|
| Qbox / QBCore | `players` | `citizenid`  |
| ESX       | `users`   | `identifier` |

Stashes, drops and confiscated inventories use the resource-owned
`w2f_stashes` table on every framework.

## Known limitations

- **ESX metadata / status:** base ESX has no core `metadata` store, so the
  item fallback's hunger/thirst writes are no-ops unless your ESX build exposes
  `xPlayer.setMeta`. Hunger/thirst are normally driven by `esx_status`.
- **Status HUD bars:** the inventory's hunger/thirst/bleed bars read
  `qbx_medical` state bags. On QBCore/ESX those bars fall back to neutral
  values; core inventory behaviour is unaffected.
- **Gangs:** only Qbox/QBCore expose gangs; on ESX the gang group is reported
  as `none`.
