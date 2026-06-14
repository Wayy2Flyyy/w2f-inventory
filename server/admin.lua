--[[ Admin item spawner (integrated from w2f_adminspawner, Wayy2Flyyy).
     /adminitems opens the AdminItems shop: every defined item that has an
     images/<name>.png, priced at $0. Admin-gated (ACE group.admin / w2finv.admin
     or qbx_core:HasGroup). ]]

local Config = {
    command   = 'adminitems',
    shopId    = 'AdminItems',
    shopLabel = 'Admin Item Spawner',
    qbxAdminGroups = { admin = 0, god = 0 },
}

local function isAdmin(src)
    if IsPlayerAceAllowed(src, 'group.admin') or IsPlayerAceAllowed(src, 'w2finv.admin')
        or IsPlayerAceAllowed(src, ('command.%s'):format(Config.command)) then
        return true
    end
    local ok, result = pcall(function() return exports.qbx_core:HasGroup(src, Config.qbxAdminGroups) end)
    return ok and result == true
end

local function itemHasImage(name)
    local candidates = { name }
    if name:lower() ~= name then candidates[#candidates + 1] = name:lower() end
    if name:sub(1, 7):upper() == 'WEAPON_' then candidates[#candidates + 1] = name:upper() end
    for i = 1, #candidates do
        local file = LoadResourceFile(CurrentResource, ('images/%s.png'):format(candidates[i]))
        if file and file ~= '' then return true end
    end
    return false
end

local function buildAdminShop()
    local inventory, skipped = {}, 0
    for name in pairs(ItemData) do
        if type(name) == 'string' then
            if itemHasImage(name) then
                inventory[#inventory + 1] = { name = name, price = 0 }
            else
                skipped = skipped + 1
            end
        end
    end
    table.sort(inventory, function(a, b) return a.name:lower() < b.name:lower() end)
    WInv.registerShop(Config.shopId, { name = Config.shopLabel, label = Config.shopLabel, inventory = inventory })
    print(('^2[w2f-inventory] %s built — %d items with images (%d skipped)^7'):format(Config.shopId, #inventory, skipped))
end

CreateThread(function()
    while not WInv or not ItemData do Wait(100) end
    Wait(500)
    buildAdminShop()
end)

lib.addCommand(Config.command, {
    help = 'Open the admin item spawner (items with images, free)',
}, function(source)
    if not isAdmin(source) then
        return TriggerClientEvent('ox_inventory:notify', source, { type = 'error', description = 'You do not have permission to use this command.' })
    end
    TriggerClientEvent('ox_inventory:openInventory', source, 'shop', { type = Config.shopId })
end)

-- expose the admin gate so the open/buy/checkout callbacks can protect the shop
WAdmin = { isAdmin = isAdmin, shopId = Config.shopId }
