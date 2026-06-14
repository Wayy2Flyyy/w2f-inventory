# w2f-inventory

A lightweight inventory resource for **Qbox / QBX** servers, built on `ox_lib` and `oxmysql`. Exposes an `ox_inventory`-compatible export and event API, so most scripts written for ox_inventory work without changes.

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- [qbx_core](https://github.com/Qbox-project/qbx_core)

## Installation

1. Drop `w2f-inventory` into your `resources` folder.
2. Add `ensure w2f-inventory` to your `server.cfg` (after its dependencies).
3. Restart the server.

## Configuration

Settings are read from `server.cfg` convars (defaults in parentheses). No file edits required.

```cfg
setr inventory:framework "qbx"                  # framework (qbx)
setr inventory:slots 50                         # player slots
setr inventory:weight 85000                     # player max weight (g)
setr inventory:dropslots 50                     # slots per ground drop
setr inventory:dropweight 100000                # weight per ground drop (g)
setr inventory:accounts ["money"]               # item-form money accounts
setr inventory:police ["police","bcso","sasp"]  # jobs treated as police
setr inventory:imagepath "nui://w2f-inventory/images"
setr inventory:clearstashes "6 MONTH"           # auto-purge old stashes
setr inventory:keys ["TAB","K","F1"]            # open-inventory keys
setr inventory:screenblur 1                      # blur behind UI (1/0)
setr inventory:dropprops 1                       # spawn props for drops (1/0)
setr inventory:dropmodel "prop_med_bag_01b"
setr inventory:loglevel 1
```

See [shared/config.lua](shared/config.lua) for the full list.

## Items

Item definitions live in `data/`:

- [data/items.lua](data/items.lua) — base items
- [data/weapons.lua](data/weapons.lua) — weapons, ammo, components
- [data/crafting.lua](data/crafting.lua) — crafting benches and recipes
- [data/shops.lua](data/shops.lua) — shop stock and locations
- [data/image_items.lua](data/image_items.lua) — image overrides

Item images are PNGs in [images/](images/) named after the item.

## Admin & moderation commands

Registered via `ox_lib` (ace-permission gated):

| Command | Description |
| --- | --- |
| `/giveitem` | Give an item to a player |
| `/removeitem` | Remove an item from a player |
| `/clearinv` | Clear a player's inventory |
| `/viewinv` | Open a player's inventory |
| `/checkinv` | Print a player's items to console |
| `/itemcount` | Count an item across a player's inventory |
| `/confiscate` | Confiscate a player's inventory |
| `/returninv` | Return a confiscated inventory |
| `/listitems` | List all registered items |

Players also have `/craft` (open a crafting bench) and the in-game keybinds from `inventory:keys`.

## Developer API

`w2f-inventory` mirrors the `ox_inventory` export surface. Examples:

```lua
exports['w2f-inventory']:AddItem(source, 'water', 1)
exports['w2f-inventory']:RemoveItem(source, 'water', 1)
exports['w2f-inventory']:GetItemCount(source, 'water')
exports['w2f-inventory']:CanCarryItem(source, 'water', 1)
exports['w2f-inventory']:RegisterStash(id, label, slots, weight)
exports['w2f-inventory']:RegisterShop(name, data)
```

Full export list in [server/main.lua](server/main.lua). Stashes and shops can also be registered from other resources via `RegisterStash` / `RegisterShop`.

## License

Provided as-is by **w2f**. See repository for terms.
