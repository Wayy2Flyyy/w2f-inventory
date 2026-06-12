-- Crafting benches. recipes: { name, count, duration(ms), ingredients = { item = amount } }
return {
    ['workbench'] = {
        label = 'Workbench',
        blip = { sprite = 566, color = 47, scale = 0.6 },
        locations = { vector3(-211.0, -1324.4, 30.9) },
        recipes = {
            { name = 'lockpick',          count = 1, duration = 5000,  ingredients = { metalscrap = 2, plastic = 1 } },
            { name = 'advancedlockpick',  count = 1, duration = 9000,  ingredients = { steel = 2, plastic = 2, spring = 1 } },
            { name = 'screwdriverset',    count = 1, duration = 6000,  ingredients = { steel = 1, plastic = 2 } },
            { name = 'repairkit',         count = 1, duration = 10000, ingredients = { steel = 5, metalscrap = 5, rubber = 2 } },
            { name = 'advancedrepairkit', count = 1, duration = 15000, ingredients = { repairkit = 1, electronics = 2, duct_tape = 1 } },
            { name = 'drill',             count = 1, duration = 15000, ingredients = { steel = 8, copper = 4, battery = 1 } },
            { name = 'zipties',           count = 2, duration = 3000,  ingredients = { plastic = 4 } },
            { name = 'duct_tape',         count = 1, duration = 3000,  ingredients = { plastic = 2, cloth = 1 } },
            { name = 'weapon_parts',      count = 1, duration = 12000, ingredients = { steel = 4, spring = 2, metalscrap = 3 } },
        },
    },
    ['electronics'] = {
        label = 'Electronics Bench',
        blip = { sprite = 521, color = 26, scale = 0.6 },
        locations = { vector3(391.4, -829.4, 29.3) },
        recipes = {
            { name = 'circuit_board', count = 1, duration = 8000,  ingredients = { electronics = 1, copper = 2 } },
            { name = 'electronickit', count = 1, duration = 10000, ingredients = { circuit_board = 1, wires = 2, battery = 1 } },
            { name = 'radio',         count = 1, duration = 12000, ingredients = { circuit_board = 1, wires = 2, plastic = 2, battery = 1 } },
            { name = 'gps',           count = 1, duration = 10000, ingredients = { circuit_board = 1, wires = 1, battery = 1, plastic = 1 } },
            { name = 'trojan_usb',    count = 1, duration = 9000,  ingredients = { circuit_board = 1, electronics = 1 } },
            { name = 'jammer',        count = 1, duration = 20000, ingredients = { circuit_board = 2, wires = 3, battery = 2, metalscrap = 2 } },
            { name = 'camera',        count = 1, duration = 12000, ingredients = { circuit_board = 1, glass = 2, plastic = 2 } },
        },
    },
    ['medical'] = {
        label = 'Medical Station',
        blip = { sprite = 51, color = 1, scale = 0.6 },
        locations = { vector3(306.4, -601.2, 43.28) },
        recipes = {
            { name = 'bandage',  count = 2, duration = 4000,  ingredients = { cloth = 2 } },
            { name = 'ifaks',    count = 1, duration = 8000,  ingredients = { bandage = 2, painkillers = 1 } },
            { name = 'firstaid', count = 1, duration = 12000, ingredients = { bandage = 3, ifaks = 1, cloth = 2 } },
            { name = 'armour',   count = 1, duration = 15000, ingredients = { cloth = 4, steel = 4, leather = 2 } },
        },
    },
    ['ammobench'] = {
        label = 'Ammo Bench',
        blip = { sprite = 110, color = 6, scale = 0.6 },
        locations = { vector3(13.0, -1098.3, 29.8) },
        recipes = {
            { name = 'ammo-9',       count = 30, duration = 6000,  ingredients = { gunpowder = 1, steel = 1, copper = 1 } },
            { name = 'ammo-45',      count = 30, duration = 6000,  ingredients = { gunpowder = 1, steel = 2, copper = 1 } },
            { name = 'ammo-shotgun', count = 20, duration = 7000,  ingredients = { gunpowder = 2, plastic = 1, steel = 1 } },
            { name = 'ammo-rifle',   count = 30, duration = 9000,  ingredients = { gunpowder = 3, steel = 2, copper = 1 } },
        },
    },
}
