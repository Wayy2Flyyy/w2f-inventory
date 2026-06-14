# w2f-inventory — Improvement & Roadmap Report

## 1. Executive Summary

**Current state.** w2f-inventory is an ox_inventory fork (ox_inventory itself is now a forwarding shim of `bridge.lua` + manifest) with a custom single-file NUI. The slot engine, parameterized SQL layer, and ACE admin gates are fundamentally sound, and performance is bounded (≤50-slot scans, dirty-flag saves, sig-cached NUI render). But the resource currently ships with a **registry-wiping syntax error**, **three economy-breaking client-trust criticals**, and a **cross-resource startup crash** that takes down the entire qbx_core QB-compat bridge. On top of that it has shed large amounts of ox_inventory behavior: vehicle storage, hotbar use, ammo/reload, attachments, containers, durability, audit logging, localization, and drop persistence/streaming are all missing or inert.

Per the architecture memory, **this server has never been booted since the rebuild** — several of these are latent-until-first-boot and will fire immediately.

**Top 5 priorities (do in this order):**

1. **Restore `[ox]/ox_inventory/data/items.lua` + `data/weapons.lua` shims** — qbx_core's QB bridge hard-`require`s them; ox_lib `require` errors hard, killing `GetCoreObject`/`QBCore.Shared.Items` and crashing every consumer (w2f-id, w2f-citation, w2f-laptop, w2f-phone, w2f-jobs). Nothing else matters until the server boots. *(C / S)*
2. **Fix `data/items.lua:104` double comma** — wipes all ~125 non-weapon item defs to weight-0 stubs; kills the weight economy, consumable status effects, and the `mm_radio` use-event. Add a startup registry assertion. *(C / S)*
3. **Lock down `wf_inventory:open`** — it resolves *any* inventory id including other online players' source numbers, enabling remote item + cash theft from anyone on the map. Plus delete the `customDrop` net event (free item/money mint) and the `inventory:server:OpenInventory` client-priced-shop path (cash mint). *(C / S–M)*
4. **Persistence + forensics floor** — debounced dirty-saves, drop persistence across restart (death drops are wiped today), set `changed=false` only on MySQL success, and add an audit-log table (the `inventory:loglevel` convar is dead — dupe forensics are currently impossible). *(H / M)*
5. **Server-side trust gates** — proximity on give/throw/drop/stash open, ammo/durability validation, shop group enforcement, count normalization, and rate limiting; these convert a dozen remaining exploits into rejections. *(H / M)*

Severity = Critical/High/Medium/Low. Effort = **S** (<½ day) / **M** (½–2 days) / **L** (multi-day).

---

## 2. Code & Performance

| Finding | Sev | Eff | Where | Action |
|---|---|---|---|---|
| Swap merge under-counts weight: cross-inv merge subtracts full destination stack (`weight+addW-subW>max`) → unlimited overweight into stashes/drops | High | S | `server/callbacks.lua:184-211` | Resolve destination branch *before* the check: `subW=0` on merge/empty, keep `subW` only on position-swap |
| Swap/buy/give/throw accept fractional counts → fractional stacks, price mismatches, desynced `getItemCount` in dependents | High | S | `server/callbacks.lua:155,327,364,419` | `count = math.floor(tonumber(...) or 0)`, reject `<1`; mirror `main.lua` `round()` into `WInv` |
| Stale `currentWeapons` slot: `updateWeapon` writes ammo/durability to whatever item now occupies the slot; swap never updates the mapping; dropped/given equipped weapon never disarms | High | M | `server/callbacks.lua:438-448`; `client/main.lua:149-179` | Guard `def.weapon` in `updateWeapon`; move/clear `currentWeapons[src]` on swap + `ox_inventory:disarm`; client disarm when synced slot loses the weapon |
| Nil deref opening owned stash when `GetPlayer` returns nil during logout → callback never responds, client `await` hangs | Med | S | `server/callbacks.lua:46` | `local p=GetPlayer(src); if not p then return false end` before reading citizenid (mirror `canAccess:22`) |
| Slot-targeted `addItem` merges stacks with mismatched metadata (used by `returnInventory`, drop placement) → destroys incoming metadata, inflates wrong identity | Med | S | `server/main.lua:194-210` | Extend guard with `metaMatches(existing, metadata, true)` before reusing `targetSlot` |
| `moneySync` runs a cross-resource `qbx_core:GetPlayer` export on *every* mutation incl. non-money items; bulk loops (return/clear) multiply it | Low | S | `server/main.lua:412-446` | Short-circuit when mutation didn't touch an account item; batch mode for bulk seed paths (one sync+push at end) |
| NUI optimistic revert clobbers newer authoritative state; optimistic apply runs against shop/crafting grids; merges ignore metadata | Low | S | `ui/inventory.html:1063-1141` | Per-slot monotonic `rev`; revert only if rev unchanged; skip optimistic path for shop/crafting/admin; match server merge rules |
| `usingItem`/`applyingMoney` guards have no error protection → one server/handler error permanently blocks all item use / money sync until restart | Low | S | `client/main.lua:183-211`; `server/main.lua:448-453` | Wrap body in `pcall`, reset flag in `finally` |
| Duplicated protected-file loader ×3; `data/crafting.lua`+`shops.lua` parsed twice; dead code (`slotList`, dup `Shops` key, unreachable server weapon-equip branch, no-op `toggleHotbar`); client `localCount` ignores metadata; `PlayerData` not reset on logout (stale multichar exports) | Low | S | `shared/items.lua:1`, `server/main.lua:746`, `client/interact.lua:1`, `client/main.lua:13` | Move loader to `shared/`; delete dead code; honor metadata via shared `metaMatches`; add `playerLoggedOut` reset + disarm |
| Drops unreachable when `dropProps=false` (open path → `getInv(nil)`→false); `spawnDrop` ignores `info.instance` | Low | S | `client/main.lua:138-141,359-381` | Client Drops registry by coords; nearest-drop pickup ≤2m regardless of props; honor instance |

---

## 3. Functions & API

| Finding | Sev | Eff | Where | Action |
|---|---|---|---|---|
| `Search` returns `false` for single-item not-found → `(false)[1]`/`pairs(false)` crashes in ox_doorlock, mm_radio (every radio-less player per `doRadioCheck`), qbx_idcard | High | S | `server/main.lua:382-396`; `client/main.lua:285-291` | Return `{}` for slots/numeric mode, `0` for count; only `false`/`nil` when inventory itself is invalid |
| `ox_inventory:itemCount` never fires on count-to-zero (changes entry is `false`) or on full reload → ox_target keeps stale target options, qbx_npwd phone stays enabled after losing phone | High | M | `client/main.lua:43-53,32-41` | Capture old slot names before mutating; recount + fire `itemCount(name,0)` for removed names; re-emit all on `setPlayerInventory` |
| Declared hooks `swapItems`/`buyItem`/`craftItem`/`createItem` never triggered (only `openInventory`/`usingItem` fire); `triggerHooks` swallows pcall errors → broken access guards fail **open** (qbx_properties bypass below depends on this) | Med | M | `server/main.lua:5,840-859` | Invoke `triggerHooks('swapItems'/'buyItem'/'craftItem')` before mutating (abort on false); log pcall failures; treat hook error as **DENY** |
| `SetMaxWeight` fires `ox_inventory:refreshMaxWeight` and `InspectInventory` fires `ox_inventory:viewInventory` — **no client handlers** → backpack/job-weight bridge half-works, inspect is a no-op | Med | S | `server/main.lua:931-935,964-971`; `client/main.lua` | Add `refreshMaxWeight` handler + NUI maxWeight msg; implement read-only `viewInventory` NUI mode or delete the export |
| Drops broadcast to `-1` and ignore `instance`/routing bucket → instanced loot (qbx_jewelery, qbx_truckrobbery, apartments) + death drops visible/lootable globally | Med | M | `server/main.lua:682-695`; `client/main.lua:359-381` | Send `createDrop` only to matching bucket; gate open server-side on bucket match (pairs with proximity fix §4) |
| `displayMetadata` is a no-op on both runtimes → qbx_idcard ID/license fields and mm_radio `radioId` never render in tooltip | Low | M | `client/main.lua:327`; `server/main.lua:983` | Store key→label map, ship in NUI `init` payload, render whitelisted metadata rows in `showTip()` |
| `invBusy` statebag not honored — only a 500ms poll auto-close; restrained/animating players can open + swap/use/give in the window (no server check either) | Low | S | `client/main.lua:97-119,345-350` | `if LocalPlayer.state.invBusy then return end` in `openInventory`/`useSlot`; reject swap/use/give server-side while `Player(src).state.invBusy` |
| Client `Search`/`GetItemCount`/`GetSlotWithItem` drop the metadata arg (server honors it) | Low | S | `client/main.lua:260-292` | Implement metadata filtering client-side or document name-only |
| `SwapSlots`/`CanSwapItem` forwarded by bridge but unregistered; `forceOpenInventory` client path, `UpdateVehicle`/`ConvertItems`/container/card/cash stubs all callerless | Low | S | `[ox]/ox_inventory/bridge.lua` vs registered exports | Register no-op shims so future third-party calls degrade gracefully; comment which forwards are stub-only |

---

## 4. Security & Anti-cheat

| Finding | Sev | Eff | Where | Action |
|---|---|---|---|---|
| `wf_inventory:open` fallback resolves **any** inventory id incl. other players' server ids; `canAccess` only rejects when `inv.groups` set (player invs never have it) → remote open + swap items **and money** out of any online player from anywhere | Critical | M | `server/callbacks.lua:40-92,84,82`; `canAccess:19-38`; `getInv` `main.lua:105-111` | Whitelist secondary-openable types only (stash via `RegisteredStashes`, shop, crafting, admin, existing drops); reject if `inv.type=='player' and inv.id~=src`; apply same in `resolveSide` |
| `ox_inventory:customDrop` plain `RegisterNetEvent` spawns arbitrary client-specified items → `customDrop('x',{{name='money',count=1e6}})` mints cash / spawns weapons | Critical | S | `server/main.lua:986-988`→`697`→`682-695` | **Delete the net event**; keep only the `CustomDrop` server export |
| `inventory:server:OpenInventory` registers a client-defined shop with client-set prices; `buyItem` trusts `shopItem.price` and skips payment when `price<=0` → $0 'money' shop mints unlimited cash | Critical | S | `server/callbacks.lua:405-413,356-391,371` | Reference only server-registered shops by key; re-validate item/price against trusted server def; never accept client inventory/prices |
| Drops have no proximity check and **sequential guessable ids** (`drop-000001`…) → loop-open every active drop on the server and drain it | High | M | `server/main.lua:682-695`; `callbacks.lua:81-92` | Require `Drops[id]` + `#(playerCoords-Drops[id].coords)<=3.0` + instance match; random-suffix ids; single-opener lock |
| `throwItem` trusts client `data.coords` verbatim → cross-map item teleport / colluder hand-off | High | S | `server/callbacks.lua:415-431` | Derive coords server-side from ped + fixed offset; reject client hint >3m from ped |
| `giveItem` skips the 2.5m proximity check when `data.target` is supplied (the exported `giveItemToTarget` always supplies it) → remote transfer to colluder | High | S | `server/callbacks.lua:323-354` | Always validate `#(srcPed-targetPed)<=3.0` + same instance after resolving target |
| `ox_inventory:updateWeapon` writes client ammo/durability with no bounds/type check, client-controlled slotId → infinite ammo, no weapon degradation, metadata corruption | High | M | `server/callbacks.lua:438-448` | Require `type(value)=='number'`; clamp ammo per weapon, durability `[0,100]`, allow durability only to decrease; require `def.weapon`; reject non-equipped slot |
| Shops enforce no `groups`/`grade`/`license` server-side → EMS armory (price-0, `groups={ambulance=0}`) open to anyone; modded client buys free gear | High | S | `server/callbacks.lua:48-55,356-391` | Enforce `shop.groups` via `canAccess` logic in **both** open and `buyItem`; add per-item `grade`/`license` checks |
| Owned-stash id scheme: `resolveStash` only suffixes `:owner` when `owner==true`; qbx_properties uses citizenid **string** → its hook regex never matches, `result.id` errors, `triggerHooks` pcall treats it as **PASS** → property stash guard silently bypassed | Med | S | `server/main.lua:642-651`; `qbx_properties/server/property.lua:10-23` | Append `:'..owner` for string owners; make hook errors **DENY** (see §3 hooks) |
| Stash open never checks registered coords → non-grouped/owned stashes browsable by name from anywhere | Med | M | `server/callbacks.lua:42-47`; `main.lua:620-664` | Enforce server-side proximity when stash def has coords |
| No per-source throttle on swap/use/give/buy/craft/throw → direct lib.callback spam burns consumables/loads MySQL; `useFallback` applies status without anim | Med | M | `server/callbacks.lua:127,250,293,323,356,393,415` | Per-source cooldown (~150-250ms) on hot callbacks; enforce server-side `usetime` busy-until timestamp |
| `ox_inventory:usedItemInternal` re-emits `usedItem` for any held slot without consuming → free repeated side effects | Med | S | `server/callbacks.lua:316-321` | Remove the net event; route legitimate uses through `wf_inventory:useItem` |
| `buyItem` count unbounded; `canCarryItem` is weight-only (and weights are 0 today) → absurd single-call stacks | Low | S | `server/callbacks.lua:364`; `main.lua:161-171` | Clamp count ≤100/stock; per-stack max in slot engine |
| `wf_inventory:equip` stores `currentWeapons[src]=slotId` with no validation → client steers which slot `updateWeapon` mutates by default | Low | S | `server/callbacks.lua:433-436` | Accept slotId only if slot holds a `def.weapon`, else clear pointer |

---

## 5. Processes (persistence, sync, saves)

| Finding | Sev | Eff | Where | Action |
|---|---|---|---|---|
| Disconnect during async load → callback still `Create()`s a ghost inventory under the OLD citizenid; next player reusing the src inherits it → cross-character item/money corruption (starter items, moneySync, saveAll all hit the ghost) | High | S | `server/main.lua:502-537` | In `loadPlayerRow` cb: `if not Loading[src] then return end` + re-validate `GetPlayer(src).citizenid==citizenid`; store per-attempt token in `Loading[src]` |
| `resolveStash` registers the inventory **before** the awaited DB load → concurrent opener sees empty stash; late load replaces items wholesale, destroying a deposit made in the window (police lockers, property stashes at shift start) | High | M | `server/main.lua:642-664` | In-flight load lock: first caller stores a `promise`, others `Await`; or load rows before `Create`, merge not replace |
| Drop inventories **never persisted** — `saveInventory` handles only `player`/`stash`; restart/crash/`restart w2f-inventory` destroys all ground loot incl. `CreateDropFromPlayer` death drops; temp/container stashes same | High | M | `server/main.lua:463-485,610,701,666` | Persist drops to `w2f_drops` (coords/model/items/created) + reload on start with TTL; at minimum convert death drops to stash rows |
| **Zero audit logging** despite `inventory:loglevel` convar; admin spawn (up to 1000×/swap), gives, shops, craft, confiscate/return, and all 40+ dependent AddItem/RemoveItem calls untracked → dupe forensics impossible | High | M | `server/main.lua` (no log calls); `shared/config.lua:26` | Logging layer keyed off `Config.logLevel`: `(ts, actor src+citizenid, action, item, count, from, to, metahash)` → `w2f_inventory_log`/ox_lib logger at callback boundaries |
| 5-min-only save loop → crash loses ≤5 min for every player/stash; per-row unsynchronized saves dupe/destroy on asymmetric cross-player trades; `changed=false` set **before** async UPDATE resolves and result unchecked → failed UPDATE silently drops dirty flag | Med | M | `server/main.lua:613-618,463-485` | Debounced dirty-save (15-30s) + 5-min sweep; save both sides of cross-inv ops together; set `changed=false` only in MySQL success cb; log failures |
| Shared-stash multi-viewer desync: `inv.open` holds only the last opener; `pushSlots` + swap `sideChanges` target one player; `inv.open` never cleared on disconnect → stale grids, pushes to dead/reused ids | Med | M | `server/main.lua:401-409`; `callbacks.lua:232-246` | Replace `inv.open` with `inv.viewers` set maintained by open/close/`playerDropped`; iterate viewers in push + swap |
| `returnInventory` ignores each `addItem` return then unconditionally DELETEs the confiscate row → released prisoner with full pockets silently loses gear; JSON-decode-failure path also deletes | Med | S | `server/main.lua:807-818` | Collect failed rows, re-save to confiscate row or `createDrop` at feet; DELETE only on full success; skip DELETE on decode failure |
| `openSecondary` (callbacks-local, keyed by src) never cleared on `playerDropped` → reused src inherits stale secondary context, can move items into an unopened container; abandoned/unopened drops live in memory + client prop forever | Med | S | `server/callbacks.lua:1,94-109`; `main.lua:681-695` | `playerDropped` handler in callbacks.lua nils `openSecondary[src]`; drop TTL sweep in 5-min loop |
| No backup/rollback: `saveInventory` does destructive `UPDATE` + upsert with no history; registry-wipe + save cycle permanently deletes unknown items via `buildItemsFromRows` filtering | Med | M | `server/main.lua:472,481,487-500` | `w2f_inventory_snapshots` (citizenid, data, ts, reason) hourly + before Confiscate/Clear; admin restore/diff command |
| Pre-rebuild stash data stranded — stashes moved to new `w2f_stashes`; no code references the legacy `ox_inventory` SQL table → every old player/property/evidence stash opens empty | Med | S | `server/main.lua:596,654,809` | One-time guarded startup migration mapping ox `(name,owner)` → `name..':'..owner`, skipping existing |
| Dead convars (`clearStashes`,`trimPlate`,`logLevel`,`screenBlur`,`giveList`), `keys[2]/[3]`, `IsPoliceJob` unused; `w2f_stashes` has no `lastupdated` so can't be pruned; opened stash + temp invs never evicted from memory → unbounded growth | Med | M | `shared/config.lua:24-30,52-55`; `server/main.lua:596,642,666` | Implement or delete each convar; add `lastupdated`, run `clearStashes` DELETE at startup; evict idle closed non-player invs; TTL temp stashes |
| Drop props broadcast to `-1`, all spawned on join in one loop; `PlaceObjectOnGroundProperly` runs on unloaded collision → distant loot clips under map + unreachable; one local object + ox_target per historical drop forever | Med | M | `server/main.lua:693`; `client/main.lua:40,359-381` | Data-only client registry + `lib.points` create/delete at ~50m; snap Z only once collision loaded; honor instance/bucket |
| MariaDB-only `ALTER TABLE players ADD COLUMN IF NOT EXISTS` fails on MySQL 8 → on a fresh MySQL host the inventory column never creates, items "work" then wipe on relog | Low | S | `server/main.lua:597` | Probe `information_schema.COLUMNS` or pcall + ignore errno 1060; refuse to load players if column missing |

---

## 6. Items & Content

| Finding | Sev | Eff | Where | Action |
|---|---|---|---|---|
| **qbx_core QB bridge crash**: `require '@ox_inventory.data.items'`/`.data.weapons` point at files deleted in the ox_inventory teardown; ox_lib `require` errors hard → `GetCoreObject`/`QBCore.Shared.Items` never register, crashing w2f-id/citation/laptop/phone/jobs and all `qb-core` consumers | Critical | S | `qbx_core/bridge/qb/{shared,server,client}/main.lua:4,7,9,19` | Restore `data/items.lua`+`data/weapons.lua` shims in `[ox]/ox_inventory` (declare in `files{}` for the client require); **shape-map** flat w2f weapons table → `Weapons`/`Components`/`Ammo`. Boot-test first time |
| **`data/items.lua:104` double comma** `clothing={...},,` → `load()` fails, registry returns `{}`, all ~125 non-weapon items become weight-0 generated stubs (dead weight economy, no status effects, radio loses `mm_radio:client:use`, consume/stack flags lost) | Critical | S | `data/items.lua:104`; `shared/items.lua` `loadData` | Delete the comma; add `if not ItemData.water then error(...)` / empty-table guard so registry breakage fails loud |
| `heavyarmor` + `police_stormram` undefined → qbx_police `setCarItemsInfo` indexes `Items()[name].name` on nil → **client script error at duty start** | High | S | `qbx_police/client/job.lua:22-36` vs `data/items.lua` | Add both defs (heavyarmor png exists); make no-arg `Items()` a metatable view falling through to `GetItemData` |
| ~25 job/robbery items undefined → weight-0 stubs, wrong labels, missing icons: 6 weed strains + 6 `_seed`, 2 corals, `moneybag`, `diamond`, `iphone/samsungphone/tablet`, `small_tv/toaster/microwave`, `firework1-4` | High | M | `data/items.lua` gaps vs `[qbx]/*` | Add "job & robbery loot" block with sensible weights (electronics 4-12kg for carry tradeoff, moneybag stack=false); generate ~16 missing PNGs |
| 7 ammo calibers have **no shop or craft source** (ammo-22/38/44/50/sniper/heavysniper/rifle2) → revolvers/snipers/military rifles dead once dry; `ammo-musket`/`ammo-laser` have no weapon | Med | S | `data/crafting.lua:44-54`; `data/shops.lua:82-104` | Add ammobench recipes for 38/44/50, gate rifle2/sniper higher or black-market; delete musket/laser or add their weapons |
| Crafting tree hard gaps: `leather` unobtainable (blocks armour, which is also unsold), `thermite` has no source (blocks Pacific/Paleto bank content), `weapon_parts` is a dead-end output (nothing consumes it) | Med | S | `data/crafting.lua:16,41`; `data/shops.lua` | Sell leather / add thermite recipe or vendor; add weapon recipes consuming weapon_parts or remove the recipe |
| 123 defined items have no `<name>.png` (most firearms, all 24 attachments, 14 ammo); 186 orphan PNGs from an unwired planned catalog (fentanyl, burner_phone, fingerprint_kit, harness…) | Med | M | `images/` (318) vs registry | Drop in ox_inventory CC0 weapon pack (names match); triage orphans — define wanted, delete rest to cut download size |
| Dead-end loot economy: `markedbills`/`black_money` have no fence/launder sink (black_money not even in `inventory:accounts`); `diving_gear`/`diving_fill` (qbx_divegear) and `harness` (qbx_lapraces) have no shop source → diving + racing jobs uncompletable | Med | S | `data/shops.lua` vs robbery/diving/race resources | Add fence/pawn entries buying markedbills/black_money at 60-70%; sell diving_gear/fill + harness |
| Evidence bag tooltip collapses multi-line metadata into one run-on line; `metadata.type` never rendered → cops can't read evidence details | Low | S | `ui/inventory.html:579,1278-1281` vs `qbx_police/server/main.lua:455-461` | Add `white-space:pre-line` to `.tip p`; render `m.type` subtitle row in `showTip()` |
| Silent generated-item fallback (weight 0, no log) masks every typo; near-duplicate legacy pairs split stacks (`armour`/`armor_vest`, `water`/`water_bottle`, `bandage`/`bandage_roll`, `jerry_can`/`WEAPON_PETROLCAN`) | Low | S | `shared/items.lua:69-93`; `data/items.lua` | Log every generated-cache miss once with `GetInvokingResource`; alias/collapse duplicate pairs; add `/w2f:audit` diffing ItemData vs started resources |

> Shop access control (groups/license enforcement) and the *content* of license-gated tiers are tracked in §4 (server enforcement) and the Phase 3 roadmap (police armory, licensed firearms).

---

## 7. Use & Abilities (gameplay features)

| Finding | Sev | Eff | Where | Action |
|---|---|---|---|---|
| **No vehicle trunk/glovebox at all** — NUI labels exist ("Vehicle trunk") but no `trunk:PLATE` stash, no vehicle keybind/target, `UpdateVehicle` is a stub. Biggest day-one loss vs ox_inventory | High | L | `server/main.lua:972`; `client/main.lua`; `ui/inventory.html:975` | `trunk`/`glovebox` types keyed by trimmed plate, persisted to `w2f_stashes`; class-based slots/weight; ox_target on bones + keybind (check qbx_vehiclekeys lock); implement `UpdateVehicle(old,new)` |
| **Police search/rob broken** — `openNearbyInventory` → `openInventory('drop',nil)` → `getInv(nil)`→false, so SearchPlayer/RobPlayer get "Can't access that" | High | S | `client/main.lua:138-141`; `callbacks.lua:81-84`; `qbx_police/client/interactions.lua:121,167` | Implement properly: closest player → serverId; server validates <3.0 + target dead/cuffed/hands-up; open their player inv as secondary |
| **Ammo items can't be used** — `useItem` returns `{used=true}`; weapons spawn `metadata.ammo=0`, only written on disarm → ammobench (4 recipes), Ammu-Nation ammo sales, 19 ammo types all dead, every gun permanently empty | High | M | `server/callbacks.lua:250-291`; `client/main.lua:154` | On `def.ammo` use: require matching equipped weapon, consume up to clip size, increment `metadata.ammo`, client `AddAmmoToPed`+progress; push ammo live on reload/fire tick |
| **Throwables equip with 0 ammo** and are never consumed → grenades/molotovs can't be thrown (and would be infinite if they could) | High | S | `client/main.lua:149-170`; `data/weapons.lua:107-117` | When `def.throwable`, give `ammo=item.count`; watcher decrements slot + re-equips next on throw |
| **Police evidence lockers fail to open** — qb-style `OpenInventory('stash',...)` forwards to `forceOpenInventory` but never registers the stash → `RegisteredStashes[id]==nil`→false; `filled_evidence_bag` has nowhere to go | High | S | `server/callbacks.lua:405-413`; `qbx_police/client/job.lua:197-206` | Auto-`registerStash(name,name,data.slots or 50,data.maxweight or 100000)` in the 'stash' branch before forcing open (gate to police groups) |
| **No hotbar use (keys 1-5) while inventory closed** — NUI draws hotkey badges + has inert `toggleHotbar` case, but only TAB/G bound; `Config.keys[2..n]` ignored | Med | M | `client/main.lua:143-147`; `ui/inventory.html` | RegisterKeyMapping `+w2fhotbar1..5` → `useSlot(n)` when closed/not dead/cuffed; wire `toggleHotbar` strip; bind alt open keys |
| **Weapon attachments can't be installed** — 25 `at_*` comps + `metadata.components={}` exist but no attach/detach path; `updateWeapon` lacks `component`; equip never applies stored comps; nothing sells/crafts them | Med | M | `data/weapons.lua:145-168`; `callbacks.lua:438-448`; `client/main.lua` equipWeapon | On `at_*` use with weapon equipped: validate via `DoesWeaponTakeWeaponComponent`, store in `metadata.components`, re-equip; loop comps → `GiveWeaponComponentToPed`; NUI strip-back entry; black-market source |
| **Durability inert + repair items dead** — per-shot wear rates defined, NUI renders condition bars stuck at 100%, but no shot tracking, no decay tick, nothing destroys at 0; `cleaningkit` ($150) and repairkit do nothing | Med | M | `client/main.lua:149-179`; `server/main.lua:45-58`; `data/weapons.lua:4` | Track `GetAmmoInPedWeapon` deltas while equipped, send `durability` using `def.durability`; block equip at 0 with broken state; make cleaningkit/repairkit usable |
| **Containers non-functional but sold** — `GetContainerFromSlot`/`setContainerProperties` stubs; `paperbag` ($1) + `clothing` bag inert | Med | M | `server/main.lua:973-974`; `data/items.lua`, `shops.lua:20` | Implement as keyed temp stashes: `metadata.container` id → `resolveStash('container:'..id)`, open as secondary, block recursion; `GetContainerFromSlot` returns it |
| **Give-item has no picker and no animation** — server silently picks nearest player ≤2.5u; `Config.giveList` read but unused → hand gear to wrong person, no feedback | Med | S | `server/callbacks.lua:323-354`; `shared/config.lua:30` | When `giveList` + >1 candidate ≤3u, return candidate list → NUI/lib context picker; else use aimed/faced ped; `givetake1_a` anim + progressBar (proximity check from §4) |
| **Crafting has no bench gating, server timing, or progression** — `bench.groups` never read, `recipe.duration` client-only → modded client loops `craftItem` for instant mass-production | Med | M | `server/main.lua:758-771`; `callbacks.lua:393-403` | Track per-player craft start, reject completions earlier than `recipe.duration`; honor `bench.groups`+grade; add `recipe.chance` + crafted-count for XP unlocks |
| **Admin tooling stops at item browser** — no give-to-player, wipe, confiscate/return command, or dupe scan; money-as-items dupe would be invisible | Low | S | `server/callbacks.lua:56-65,132-146`; `server/main.lua` (exports exist) | ACE-gated `/giveitem`, `/wipeinv`, bind `/confiscate`+`/returninv`, `/dupescan` over players.inventory + w2f_stashes JSON for repeated weapon serials / over-cap money |
| **NUI lacks search/filter and ignores `def.buttons`** — `BuildItemCatalog` ships `buttons` but context menu is hardcoded Use/Give/Split/Throw/Drop | Low | S | `ui/inventory.html`; `shared/items.lua:110-121` | Search input dimming non-matches; append `CATALOG[name].buttons` (filtered by group) → `customButton` callback relayed as `TriggerEvent` |

> `displayMetadata` and `InspectInventory`/`viewInventory` dead client paths are tracked in §3 (export behavior).

---

## 8. Build Next — Roadmap

### Phase 1 — Stability & Security hard fixes *(blocker clearance; do before any boot-facing testing)*
**Goal:** server boots cleanly, no remote theft/mint, no silent data loss.
- **Restore ox_inventory data shims** (`data/items.lua`+`data/weapons.lua` in `[ox]/ox_inventory`, declared in `files{}`, with flat→`Weapons`/`Components`/`Ammo` shape mapping) — unblocks qbx_core bridge + all `GetCoreObject` consumers. *(S, but boot-test heavy)*
- **Fix `items.lua:104`** + startup registry assertion. *(S)*
- **`wf_inventory:open` lockdown** — whitelist secondary types, reject `player≠src`, proximity/instance for drops + stashes, random-suffix drop ids, single-opener lock. *(M)*
- **Kill injection surfaces** — delete `customDrop` + `usedItemInternal` net events; restrict `inventory:server:OpenInventory` to server-registered shops; enforce `shop.groups` in open+buyItem. *(S–M)*
- **Trust gates** — give/throw server-derived/validated coords, `updateWeapon` type+clamp+`def.weapon`, equip slot validation, buyItem count clamp, count normalization (`math.floor`), per-source rate limiting. *(M)*
- **Concurrency & corruption** — disconnect-during-load token guard; `resolveStash` in-flight promise lock; swap weight-merge fix; `deepEqual` metadata compare (replace `json.encode`); addItem slot-merge metadata guard; stale `currentWeapons`/disarm-on-loss. *(M)*
- **Persistence floor** — debounced dirty-save + `changed=false` only on MySQL success + failure logging; save both sides of cross-inv ops; drop persistence incl. death drops; MySQL8-safe DDL; nil-deref guard at stash open. *(M)*
- **Forensics** — `w2f_inventory_log` keyed off `Config.logLevel`; `w2f_inventory_snapshots` for rollback. *(M)*
**Rough effort: ~1.5-2 weeks.**

### Phase 2 — Core gameplay parity *(restore the ox_inventory feel)*
**Deliverables:**
- **Vehicle trunk/glovebox** — `trunk:PLATE`/`glovebox:PLATE` stashes, class-based capacity table, ox_target+keybind opening, lock-state check, `UpdateVehicle` rename. *(L)*
- **Hotbar keys 1-5** while closed + `toggleHotbar` strip + alt open keys. *(M)*
- **Ammo/reload** flow + **throwable** consumption + live ammo push on reload/fire. *(M)*
- **Weapon attachments** install/strip (`metadata.components` + `GiveWeaponComponentToPed` + `updateWeapon('component')`) + black-market source. *(M)*
- **Containers** (paperbag/clothing/toolbox → keyed temp stashes, `GetContainerFromSlot`). *(M)*
- **Police loops** — `openNearbyInventory` search/rob + evidence locker auto-register. *(S)*
- **Sync/dependent fixes** — `viewers` set for multi-viewer stashes, `itemCount`-on-zero, `Search` returns `{}`/`0`. *(M)*
**Rough effort: ~2-3 weeks.**

### Phase 3 — Depth *(progression, admin, polish)*
**Deliverables:**
- **Durability** decay + cleaningkit/repairkit + broken-weapon gating. *(M)*
- **Crafting XP/progression** + server-enforced duration/bench-groups/chance. *(M)*
- **Shop gating + content** — group/grade/`license` enforcement, licensed firearm tiers, police armory; fence for markedbills/black_money; diving/harness sources; ammo caliber recipes; leather/thermite/weapon_parts fixes. *(M)*
- **Admin suite** — `/giveitem` `/wipeinv` `/confiscate` `/returninv` `/dupescan` + read-only `InspectInventory` NUI view. *(S–M)*
- **NUI UX** — per-grid search/filter, `def.buttons` context entries, `displayMetadata` tooltip, multi-line evidence tooltip. *(S–M)*
- **Localization** — `lib.locale`, `locales/en.json`, NUI dictionary in `init` payload. *(M)*
- **Drop streaming** via `lib.points` + TTL/expiry + instance/bucket scoping. *(M)*
- **Housekeeping** — legacy ox_inventory stash migration; implement/delete dead convars (`clearStashes` pruning with `lastupdated`, idle-inv eviction, `keys[2..3]`); image pack + orphan triage. *(M)*
**Rough effort: ~3-4 weeks.**

---

## 9. Quick Wins (<1h each)

1. `data/items.lua:104` — delete the stray comma (unblocks the entire item economy).
2. Add startup assertion: empty registry → hard `error()` (`shared/items.lua` after register loop).
3. Delete `RegisterNetEvent('ox_inventory:customDrop', ...)` (`server/main.lua:986`) — kills the cash/item mint.
4. Delete `RegisterNetEvent('ox_inventory:usedItemInternal', ...)` (`callbacks.lua:316`).
5. Restrict `inventory:server:OpenInventory` to server-registered shop keys (`callbacks.lua:405`).
6. Nil-check `GetPlayer(src)` before citizenid at `callbacks.lua:46`.
7. Reorder swap weight check so merge/empty uses `subW=0` (`callbacks.lua:184-211`).
8. `count = math.floor(...)`, reject `<1` in swap/buy/give/throw (`callbacks.lua:155,327,364,419`).
9. Replace `json.encode` metadata compare with `deepEqual` in swap (`callbacks.lua:206-207`).
10. `updateWeapon`: add `if not def or not def.weapon then return end` + `type(value)=='number'` clamp (`callbacks.lua:438`).
11. `equip`: accept slotId only if it holds a `def.weapon` (`callbacks.lua:433`).
12. Append `:'..owner` for string owners in `resolveStash` (`server/main.lua:642-651`) — closes qbx_properties bypass.
13. Make `triggerHooks` log pcall failures and treat error as DENY (`server/main.lua:840-859`).
14. Auto-`registerStash` in the `OpenInventory('stash')` branch (`callbacks.lua:405-413`) — restores evidence lockers.
15. Add `heavyarmor` + `police_stormram` item defs (stops qbx_police duty-start crash).
16. Remove `paperbag` from `data/shops.lua:20` until containers exist.
17. Clamp `buyItem` count ≤100/stock (`callbacks.lua:364`).
18. `pcall` the `usingItem` body + reset flag (`client/main.lua:183`); same for `applyingMoney` (`server/main.lua:448`).
19. Clear `openSecondary[src]` (+ viewers) in a `playerDropped` handler inside `callbacks.lua`.
20. `giveItem`: add the ≤3.0m proximity check on the explicit-target path (`callbacks.lua:323-354`).
21. Add `white-space:pre-line` to `.tip p` (`ui/inventory.html:579`) + render `metadata.type` — fixes evidence readability.
22. Register no-op `SwapSlots`/`CanSwapItem` shims so future bridge callers degrade gracefully.