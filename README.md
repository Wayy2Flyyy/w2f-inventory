<div align="center">

# 🎒 w2f-inventory

### A fast, modern, slot-and-weight inventory for FiveM — built to run anywhere.

**One inventory. Three frameworks. Zero rewrites.**

[![Framework](https://img.shields.io/badge/Qbox-supported-3b82f6?style=flat-square)](#-framework-support)
[![Framework](https://img.shields.io/badge/QBCore-supported-22c55e?style=flat-square)](#-framework-support)
[![Framework](https://img.shields.io/badge/ESX-supported-f59e0b?style=flat-square)](#-framework-support)

</div>

---

## ✨ Why w2f-inventory?

Most inventories pick a side. This one doesn't. A single, isolated **framework
bridge** normalizes **Qbox**, **QBCore** and **ESX** behind one clean API, so
the same resource boots on any of them — selected by a convar, or auto-detected
for you. Swap frameworks and your inventory just keeps working.

> Under the hood it speaks the **`ox_inventory` export language**, so scripts
> that already target ox_inventory feel right at home.

---

## 🚀 Features

| | |
|---|---|
| 🧩 **Multi-framework** | Qbox · QBCore · ESX, auto-detected or convar-pinned |
| ⚖️ **Slots & weight** | Configurable capacity, stacking, per-item weight |
| 🎒 **Drops** | World props you can see, target and loot (`ox_target` aware) |
| 🗄️ **Stashes** | Persistent, ownable, shareable and job/gang-gated |
| 🛒 **Shops** | Map blips, locations, cash **or** bank checkout, basket buying |
| 🔨 **Crafting** | Recipe benches with ingredients, durations and progress bars |
| 🔫 **Weapons** | Durability, ammo, serials, components — all in metadata |
| 💵 **Money as items** | Cash/bank/black-money kept in sync with your framework |
| 🤝 **Give & throw** | Hand items to nearby players or toss them on the ground |
| 🩹 **Status HUD** | Health, armor, hunger, thirst, stamina, bleed & limb damage |
| 🛠️ **Admin spawner** | `/adminitems` — every item with an image, free, admin-gated |
| 🪝 **Hooks & exports** | Register hooks and call a familiar inventory API |

---

## 📦 Requirements

- [ox_lib](https://github.com/overextended/ox_lib)
- [oxmysql](https://github.com/overextended/oxmysql)
- One framework: **`qbx_core`**, **`qb-core`**, or **`es_extended`**
- *(optional)* [ox_target](https://github.com/overextended/ox_target) — richer drop & shop interactions

---

## ⚡ Installation

```bash
# 1. Drop the resource into your resources folder
cd resources/[w2f]
git clone https://github.com/Wayy2Flyyy/w2f-inventory.git
```

```cfg
# 2. Make sure your framework starts FIRST, then this resource
ensure ox_lib
ensure oxmysql
ensure qbx_core          # or qb-core / es_extended
ensure w2f-inventory

# 3. (Optional) pin the framework — otherwise it auto-detects
setr inventory:framework auto   # qbx | qb | esx | auto
```

The required database column and the `w2f_stashes` table are created
**automatically** on first start. No SQL imports to run. ✅

---

## 🧱 Framework support

`auto` detects whichever core is running (`qbx_core` → `qb-core` →
`es_extended`). Pin it explicitly if your start order is unusual:

```cfg
setr inventory:framework qbx   # Qbox
setr inventory:framework qb    # QBCore
setr inventory:framework esx   # ESX
```

Inventories persist on the framework's character table — `players.inventory`
(Qbox/QBCore) or `users.inventory` (ESX). Full details and known limitations
live in **[FRAMEWORKS.md](FRAMEWORKS.md)**.

---

## ⚙️ Configuration

Everything is tunable with convars in `server.cfg` — no editing Lua required.

| Convar | Default | What it does |
|---|---|---|
| `inventory:framework` | `auto` | `qbx` · `qb` · `esx` · `auto` |
| `inventory:slots` | `50` | Player inventory slots |
| `inventory:weight` | `85000` | Player max weight (grams) |
| `inventory:dropslots` | `50` | Slots per ground drop |
| `inventory:dropweight` | `100000` | Max weight per drop |
| `inventory:accounts` | `["money"]` | Money item accounts |
| `inventory:police` | `["police","bcso","sasp"]` | Police job names |
| `inventory:keys` | `["TAB","K","F1"]` | Open-inventory keybinds |
| `inventory:dropprops` | `1` | Spawn physical props for drops |
| `inventory:itemnotify` | `1` | Show item add/remove toasts |
| `inventory:screenblur` | `1` | Blur the screen while open |

```cfg
# Example
setr inventory:slots 60
setr inventory:weight 120000
setr inventory:framework qbx
```

---

## 🎮 Controls & commands

| Input | Action |
|---|---|
| **TAB** | Open / close inventory |
| **G** | Throw the equipped item |
| `/adminitems` | Open the admin item spawner *(admin only)* |
| `/craft [bench]` | Open a crafting bench |

---

## 🔌 Drop-in compatibility

w2f-inventory exposes the inventory exports your scripts already expect:

```lua
-- Server
exports['w2f-inventory']:AddItem(src, 'water', 1)
exports['w2f-inventory']:RemoveItem(src, 'bread', 2)
local count = exports['w2f-inventory']:GetItemCount(src, 'lockpick')
exports['w2f-inventory']:RegisterStash('gang_stash', 'Gang Locker', 100, 500000)

-- Client
local items  = exports['w2f-inventory']:GetPlayerItems()
local weight = exports['w2f-inventory']:GetPlayerWeight()
exports['w2f-inventory']:openShop({ type = 'general' })
```

Hooks let you intercept and veto inventory actions:

```lua
exports['w2f-inventory']:registerHook('swapItems', function(payload)
    -- return false to block the swap
end)
```

---

## 🗂️ Project layout

```
w2f-inventory/
├── shared/      config + item registry
├── server/      framework bridge, core logic, callbacks, admin spawner
├── client/      framework bridge, UI glue, status HUD, world interactions
├── data/        items · weapons · crafting · shops  (pure data, easy to edit)
├── ui/          NUI inventory interface
└── images/      item icons
```

---

<div align="center">

Made with ❤️ by **Wayy2Flyyy**

*Runs on Qbox, QBCore and ESX — so you don't have to choose.*

</div>
