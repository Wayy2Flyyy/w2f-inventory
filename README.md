# w2f-inventory

<img width="923" height="465" alt="image" src="https://github.com/user-attachments/assets/2e7be454-1285-4d45-8822-830b909b67f2" />
<img width="1204" height="668" alt="image" src="https://github.com/user-attachments/assets/ade673e0-dd65-48d1-8052-4b553296764e" />


## Installation

1. Drop `w2f-inventory` into your `resources` folder.
2. Add `ensure w2f-inventory` to your `server.cfg` (after its dependencies).
3. Restart the server.

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
