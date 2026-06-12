<div align="center">

# 🎒 w2f-inventory

**A fast, modern slot & weight inventory for FiveM — one resource, three frameworks.**

**One inventory. Three frameworks. Zero rewrites.**

[![Framework](https://img.shields.io/badge/Qbox-supported-3b82f6?style=flat-square)](#-framework-support)
[![Framework](https://img.shields.io/badge/QBCore-supported-22c55e?style=flat-square)](#-framework-support)
[![Framework](https://img.shields.io/badge/ESX-supported-f59e0b?style=flat-square)](#-framework-support)

</div>

---

## Features

- 🧩 **Qbox · QBCore · ESX** — auto-detected or pinned by convar
- ⚖️ Slots, weight, stacking
- 🎒 Lootable ground drops (props + `ox_target`)
- 🗄️ Persistent stashes — ownable, shared, job/gang locked
- 🛒 Shops with blips, cash/bank checkout
- 🔨 Crafting benches with recipes
- 🔫 Weapons with durability, ammo, serials, attachments
- 💵 Cash/bank/black-money synced as items
- 🤝 Give & throw items
- 🩹 Status HUD (health, hunger, thirst, stamina, limbs)
- 🛠️ `/adminitems` spawner

---

## Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- A framework: `qbx_core`, `qb-core`, or `es_extended`
- *(optional)* [ox_target](https://github.com/overextended/ox_target)

---

## Install

```cfg
ensure ox_lib
ensure oxmysql
ensure qbx_core          # or qb-core / es_extended
ensure w2f-inventory
```

The DB column and `w2f_stashes` table are created automatically. No SQL to import.

---

## Framework

Auto-detected by default. Pin it if needed:

```cfg
setr inventory:framework auto   # qbx | qb | esx | auto
```

Inventories save to `players.inventory` (Qbox/QBCore) or `users.inventory` (ESX).
See **[FRAMEWORKS.md](FRAMEWORKS.md)**.

---

## Config

Set via convars in `server.cfg`:

| Convar | Default | Description |
|---|---|---|
| `inventory:framework` | `auto` | `qbx` · `qb` · `esx` · `auto` |
| `inventory:slots` | `50` | Player slots |
| `inventory:weight` | `85000` | Max weight (g) |
| `inventory:dropslots` | `50` | Slots per drop |
| `inventory:dropweight` | `100000` | Max drop weight |
| `inventory:keys` | `["TAB","K","F1"]` | Open keybinds |
| `inventory:dropprops` | `1` | Spawn drop props |
| `inventory:itemnotify` | `1` | Add/remove toasts |
| `inventory:screenblur` | `1` | Blur while open |

---

## Controls

| Input | Action |
|---|---|
| **TAB** | Open / close |
| **G** | Throw equipped item |
| `/adminitems` | Item spawner (admin) |
| `/craft [bench]` | Open crafting bench |

---

## Exports

```lua
-- Server
exports['w2f-inventory']:AddItem(src, 'water', 1)
exports['w2f-inventory']:RemoveItem(src, 'bread', 2)
exports['w2f-inventory']:GetItemCount(src, 'lockpick')
exports['w2f-inventory']:RegisterStash('gang_stash', 'Gang Locker', 100, 500000)

-- Client
exports['w2f-inventory']:GetPlayerItems()
exports['w2f-inventory']:openShop({ type = 'general' })
```

---

<div align="center">

Made with ❤️ by **Wayy2Flyyy**

</div>
