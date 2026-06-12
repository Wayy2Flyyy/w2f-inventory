local openSecondary = {}

local AdminCatalog = {}
for name in pairs(ItemData) do AdminCatalog[#AdminCatalog + 1] = name end
table.sort(AdminCatalog)

local function getInv(x) return WInv.getInv(x) end
local function slotReturn(inv, s) return WInv.slotReturn(inv, s) end

local function invPayload(inv)
    local items = {}
    for slotId in pairs(inv.items) do items[slotId] = slotReturn(inv, slotId) end
    return {
        id = inv.id, type = inv.type, label = inv.label,
        slots = inv.slots, maxWeight = inv.maxWeight, items = items,
    }
end

local function canAccess(src, inv)
    if not inv then return false end
    if inv.groups then
        local player = exports.qbx_core:GetPlayer(src)
        if not player then return false end
        local job = player.PlayerData.job
        local gang = player.PlayerData.gang
        local ok = false
        for g, minGrade in pairs(inv.groups) do
            if (job and job.name == g and (job.grade.level or 0) >= (minGrade or 0))
            or (gang and gang.name == g and (gang.grade.level or 0) >= (minGrade or 0)) then ok = true break end
        end
        if not ok then return false end
    end

    if not WInv.triggerHooks('openInventory', {
        source = src, inventoryId = inv.id, inventoryType = inv.type,
    }) then return false end
    return true
end

lib.callback.register('wf_inventory:open', function(src, invType, data)
    local inv
    if invType == 'stash' then
        local id = type(data) == 'table' and (data.id or data[1]) or data
        local def = WInv.RegisteredStashes[id]
        if not def then return false end
        local owner = def.owner == true and (exports.qbx_core:GetPlayer(src).PlayerData.citizenid) or nil
        inv = WInv.resolveStash(id, owner)
    elseif invType == 'shop' then
        local shopType = type(data) == 'table' and (data.type or data.id) or data
        local shop = WInv.Shops[shopType]
        if not shop then return false end
        if WAdmin and shopType == WAdmin.shopId and not WAdmin.isAdmin(src) then return false end
        openSecondary[src] = 'shop:' .. tostring(shopType)
        TriggerEvent('ox_inventory:openedInventory', src, openSecondary[src])
        return { id = 'shop:' .. tostring(shopType), type = 'shop', label = shop.name or shop.label or 'Shop',
                 slots = #shop.inventory, maxWeight = 1000000, items = shop.inventory, shopType = shopType }
    elseif invType == 'admin' then
        if not IsPlayerAceAllowed(src, 'w2finv.admin') then return false end
        local items = {}
        for i = 1, #AdminCatalog do
            local def = GetItemData(AdminCatalog[i])
            items[i] = { slot = i, name = def.name, count = 1, weight = def.weight or 0, metadata = {} }
        end
        openSecondary[src] = 'admin'
        TriggerEvent('ox_inventory:openedInventory', src, 'admin')
        return { id = 'admin', type = 'admin', label = 'All Items', slots = #items, maxWeight = 10000000, items = items }
    elseif invType == 'crafting' then
        local id = type(data) == 'table' and (data.id or data[1]) or data
        local bench = WInv.CraftingBenches[id]
        if not bench then return false end
        openSecondary[src] = 'crafting:' .. tostring(id)
        TriggerEvent('ox_inventory:openedInventory', src, openSecondary[src])
        local items = {}
        for i = 1, #bench.recipes do
            local r = bench.recipes[i]
            local def = GetItemData(r.name) or {}
            items[i] = { slot = i, name = r.name, count = r.count or 1, weight = def.weight or 0,
                metadata = { ingredients = r.ingredients, duration = r.duration, recipe = i } }
        end
        return { id = 'crafting:' .. tostring(id), type = 'crafting', label = bench.label or 'Crafting',
                 slots = #items, maxWeight = 1000000, items = items, benchId = id }
    elseif invType == 'drop' then
        local id = data and (data.id or data)
        inv = getInv(id)
        if not inv or inv.type ~= 'drop' then return false end
        local d = WInv.Drops[id]
        if d and d.coords then
            local pc = GetEntityCoords(GetPlayerPed(src))
            if #(pc - vector3(d.coords.x, d.coords.y, d.coords.z)) > 3.0 then return false end
        end
    else
        return false
    end
    if not inv then return false end
    if not canAccess(src, inv) then return false end
    inv.open = src
    openSecondary[src] = inv.id
    TriggerEvent('ox_inventory:openedInventory', src, inv.id)
    return invPayload(inv)
end)

lib.callback.register('wf_inventory:close', function(src)
    local id = openSecondary[src]
    if id then
        local inv = getInv(id)
        if inv then
            if inv.open == src then inv.open = false end
            if inv.type == 'drop' then

                if not next(inv.items) then WInv.Drops[inv.id] = nil; TriggerClientEvent('ox_inventory:removeDrop', -1, inv.id); WInv.Inventories[inv.id] = nil end
            end
        end
        TriggerEvent('ox_inventory:closedInventory', src, id)
        openSecondary[src] = nil
    end
    return true
end)

local function resolveSide(src, sideType)
    if sideType == 'player' then return getInv(src) end
    if sideType == 'newdrop' then return 'newdrop' end
    local id = openSecondary[src]
    return id and getInv(id) or nil
end

local function pushBoth(playerInv, secondInv, src, changesPlayer, changesSecond)
    if changesPlayer and next(changesPlayer) then
        TriggerClientEvent('wf_inventory:sync', src, changesPlayer, playerInv.weight, playerInv.id)
    end
    if secondInv and changesSecond and next(changesSecond) then
        TriggerClientEvent('wf_inventory:syncSecondary', src, secondInv.id, changesSecond, secondInv.weight)
    end
end

lib.callback.register('wf_inventory:swap', function(src, data)
    local playerInv = getInv(src)
    if not playerInv then return false end
    if type(data) ~= 'table' or type(data.fromSlot) ~= 'number' or type(data.toSlot) ~= 'number' then return false end

    if openSecondary[src] == 'admin' and (data.fromType ~= 'player' or data.toType ~= 'player') then
        if not IsPlayerAceAllowed(src, 'w2finv.admin') then return false end
        if data.fromType ~= 'player' then
            local name = AdminCatalog[data.fromSlot]
            if not name then return false end
            local cnt = math.max(1, math.min(tonumber(data.count) or 1, 1000))
            local ok = WInv.addItem(playerInv, name, cnt)
            return ok and true or false
        end
        local slot = playerInv.items[data.fromSlot]
        if not slot then return false end
        local cnt = math.min(tonumber(data.count) or slot.count, slot.count)
        local ok = WInv.removeItem(playerInv, slot.name, cnt, slot.metadata, data.fromSlot, false, true)
        return ok and true or false
    end

    local fromInv = resolveSide(src, data.fromType)
    if fromInv == 'newdrop' then return false end
    if not fromInv then return false end

    local fromSlot = fromInv.items[data.fromSlot]
    if not fromSlot then return false end
    local def = GetItemData(fromSlot.name)
    local count = math.min(tonumber(data.count) or fromSlot.count, fromSlot.count)
    if count <= 0 then return false end

    if IsAccountItem[fromSlot.name] and (data.toType ~= 'player' or fromInv.type ~= 'player') then
        return false
    end

    if fromInv.type == 'shop' then return false end

    if data.toType == 'newdrop' then
        local ped = GetPlayerPed(src)
        local coords = GetEntityCoords(ped)
        local meta = fromSlot.metadata
        local ddef = GetItemData(fromSlot.name)
        local model = (ddef.client and ddef.client.prop) or Config.dropModel
        local dropId = WInv.createDrop('drop',
            { { name = fromSlot.name, count = count, metadata = meta } }, vec3(coords.x, coords.y, coords.z), nil, nil, nil, model)
        if not dropId then return false end
        WInv.removeItem(fromInv, fromSlot.name, count, meta, data.fromSlot, false, true)
        return true
    end

    local toInv = resolveSide(src, data.toType)
    if not toInv or toInv == 'newdrop' then return false end
    if data.fromSlot < 1 or data.fromSlot > fromInv.slots then return false end
    if data.toSlot < 1 or data.toSlot > toInv.slots then return false end

    local toSlot = toInv.items[data.toSlot]

    if toInv.id ~= fromInv.id then
        local addW = (fromSlot.metadata and fromSlot.metadata.weight or def.weight or 0) * count
        local subW = 0
        if toSlot then
            local tdef = GetItemData(toSlot.name)
            subW = (toSlot.metadata and toSlot.metadata.weight or tdef.weight or 0) * toSlot.count
        end
        if toInv.weight + addW - subW > toInv.maxWeight then return false, 'cannot_carry' end
    end

    local changesFrom, changesTo = {}, {}

    if not toSlot then

        if count == fromSlot.count then
            toInv.items[data.toSlot] = { name = fromSlot.name, count = count, slot = data.toSlot, metadata = fromSlot.metadata }
            fromInv.items[data.fromSlot] = nil
        else
            toInv.items[data.toSlot] = { name = fromSlot.name, count = count, slot = data.toSlot,
                metadata = fromSlot.metadata and json.decode(json.encode(fromSlot.metadata)) or {} }
            fromSlot.count = fromSlot.count - count
        end
    elseif toSlot.name == fromSlot.name and def.stack
        and json.encode(toSlot.metadata or {}) == json.encode(fromSlot.metadata or {}) then

        toSlot.count = toSlot.count + count
        if count == fromSlot.count then fromInv.items[data.fromSlot] = nil
        else fromSlot.count = fromSlot.count - count end
    else

        if count ~= fromSlot.count then return false end
        if toInv.id ~= fromInv.id then

            local tdef = GetItemData(toSlot.name)
            local incomingW = (toSlot.metadata and toSlot.metadata.weight or tdef.weight or 0) * toSlot.count
            local outgoingW = (fromSlot.metadata and fromSlot.metadata.weight or def.weight or 0) * fromSlot.count
            if fromInv.weight - outgoingW + incomingW > fromInv.maxWeight then return false, 'cannot_carry' end
        end
        fromInv.items[data.fromSlot] = { name = toSlot.name, count = toSlot.count, slot = data.fromSlot, metadata = toSlot.metadata }
        toInv.items[data.toSlot] = { name = fromSlot.name, count = fromSlot.count, slot = data.toSlot, metadata = fromSlot.metadata }
    end

    WInv.syncInventory(fromInv)
    if toInv.id ~= fromInv.id then WInv.syncInventory(toInv) end

    changesFrom[data.fromSlot] = fromInv.items[data.fromSlot] and slotReturn(fromInv, data.fromSlot) or false
    changesTo[data.toSlot]     = toInv.items[data.toSlot] and slotReturn(toInv, data.toSlot) or false

    local function sideChanges(inv, ch)
        if inv.id == playerInv.id then
            TriggerClientEvent('wf_inventory:sync', src, ch, playerInv.weight, playerInv.id)
        else
            TriggerClientEvent('wf_inventory:syncSecondary', src, inv.id, ch, inv.weight)
        end
    end
    sideChanges(fromInv, changesFrom)
    if toInv.id ~= fromInv.id then sideChanges(toInv, changesTo)
    else
        local merged = {}
        merged[data.fromSlot] = changesFrom[data.fromSlot]
        merged[data.toSlot] = changesTo[data.toSlot]
        sideChanges(fromInv, merged)
    end
    return true
end)

lib.callback.register('wf_inventory:useItem', function(src, slotId)
    local inv = getInv(src); if not inv then return false end
    local slot = inv.items[slotId]; if not slot then return false end
    local def = GetItemData(slot.name)

    if def.weapon then
        WInv.currentWeapons[src] = slotId
        TriggerClientEvent('ox_inventory:currentWeapon', src, slotReturn(inv, slotId))
        return { equip = true }
    end

    if not WInv.triggerHooks('usingItem', { source = src, item = slot.name, slot = slotId }) then return false end

    local item = {
        name = slot.name, slot = slotId, count = slot.count, amount = slot.count,
        metadata = slot.metadata, info = slot.metadata, label = def.label, type = 'item',
    }

    TriggerEvent('ox_inventory:usedItem', src, slot.name, slotId, slot.metadata)

    -- the framework usable-item callback owns the anim, removal and effects
    local cb
    local ok = pcall(function() cb = exports.qbx_core:CanUseItem(slot.name) end)
    if ok and cb then
        pcall(cb, src, item)
        return { used = true }
    end

    -- ox-native fallback: the item's server export handles its own removal
    if def.server and def.server.export then
        local res, fn = def.server.export:match('^(.-)%.(.+)$')
        if res and fn then pcall(function() exports[res][fn](src, item) end) end
        return { used = true, clientEvent = def.client and def.client.event }
    end

    local cl = def.client or {}
    if cl.status then
        return { fallback = true, usetime = cl.usetime or 2500, label = def.label, clientEvent = cl.event }
    end

    return { used = true, clientEvent = cl.event }
end)

lib.callback.register('wf_inventory:useFallback', function(src, slotId)
    local inv = getInv(src); if not inv then return false end
    local slot = inv.items[slotId]; if not slot then return false end
    local def = GetItemData(slot.name)
    local okCb, cb = pcall(function() return exports.qbx_core:CanUseItem(slot.name) end)
    if okCb and cb then return false end
    local consume = def.consume
    if consume == nil then consume = 1 end
    if consume ~= 0 then
        if not WInv.removeItem(inv, slot.name, 1, slot.metadata, slotId, false, true) then return false end
    end
    local st = def.client and def.client.status
    if st then
        local player = exports.qbx_core:GetPlayer(src)
        if player then
            local md = player.PlayerData.metadata or {}
            if st.hunger then player.Functions.SetMetaData('hunger', math.min(100, (md.hunger or 0) + st.hunger / 10000)) end
            if st.thirst then player.Functions.SetMetaData('thirst', math.min(100, (md.thirst or 0) + st.thirst / 10000)) end
        end
    end
    return true
end)

RegisterNetEvent('ox_inventory:usedItemInternal', function(slotId)
    local src = source
    local inv = getInv(src); if not inv then return end
    local slot = inv.items[slotId]; if not slot then return end
    TriggerEvent('ox_inventory:usedItem', src, slot.name, slotId, slot.metadata)
end)

lib.callback.register('wf_inventory:giveItem', function(src, data)
    local inv = getInv(src); if not inv then return false end
    local slotId, count, targetId = data.slot, data.count, data.target
    local slot = inv.items[slotId]; if not slot then return false end
    count = math.min(tonumber(count) or slot.count, slot.count)
    if not targetId then

        local ped = GetPlayerPed(src)
        local coords = GetEntityCoords(ped)
        local closest, dist
        for _, pid in ipairs(GetPlayers()) do
            pid = tonumber(pid)
            if pid ~= src then
                local d = #(coords - GetEntityCoords(GetPlayerPed(pid)))
                if d < 2.5 and (not dist or d < dist) then closest, dist = pid, d end
            end
        end
        targetId = closest
    end
    if not targetId then return false end
    if targetId == src then return false end
    local tped = GetPlayerPed(targetId)
    if tped == 0 or #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(tped)) > 3.0 then return false end
    local targetInv = getInv(targetId); if not targetInv then return false end
    if not WInv.canCarryItem(targetInv, GetItemData(slot.name), count, slot.metadata) then
        TriggerClientEvent('ox_inventory:notify', src, { type = 'error', description = 'Target can\'t carry that' })
        return false
    end
    local ok = WInv.removeItem(inv, slot.name, count, slot.metadata, slotId, false, true)
    if ok then
        WInv.addItem(targetInv, slot.name, count, slot.metadata)
        TriggerClientEvent('ox_inventory:itemNotify', targetId, { GetItemData(slot.name), 'ui_added', count })
    end
    return ok
end)

lib.callback.register('wf_inventory:buyItem', function(src, data)
    local inv = getInv(src); if not inv then return false end
    local shopId = openSecondary[src]
    local shopType = shopId and shopId:gsub('^shop:', '')
    local shop = shopType and WInv.Shops[shopType]
    if not shop then return false end
    if WAdmin and shopType == WAdmin.shopId and not WAdmin.isAdmin(src) then return false end
    local shopItem = shop.inventory[data.fromSlot]
    if not shopItem then return false end
    local count = math.max(1, tonumber(data.count) or 1)
    local price = (shopItem.price or 0) * count
    local method = data.payment == 'bank' and 'bank' or 'cash'
    if not WInv.canCarryItem(inv, GetItemData(shopItem.name), count, shopItem.metadata) then
        TriggerClientEvent('ox_inventory:notify', src, { type = 'error', description = 'Too heavy to carry' })
        return false
    end
    if price > 0 then
        if method == 'bank' then
            local player = exports.qbx_core:GetPlayer(src)
            if not player or (player.PlayerData.money.bank or 0) < price then
                TriggerClientEvent('ox_inventory:notify', src, { type = 'error', description = 'Not enough on card' })
                return false
            end
            player.Functions.RemoveMoney('bank', price, 'w2f-inventory shop')
        else
            if WInv.getItemCount(inv, 'money') < price then
                TriggerClientEvent('ox_inventory:notify', src, { type = 'error', description = 'Not enough cash' })
                return false
            end
            WInv.removeItem(inv, 'money', price, nil, nil, false, false)
        end
    end
    WInv.addItem(inv, shopItem.name, count, shopItem.metadata)
    local label = (GetItemData(shopItem.name) or {}).label or shopItem.name
    TriggerClientEvent('ox_inventory:notify', src, { type = 'success', description = ('Bought %dx %s'):format(count, label) })
    return true
end)

lib.callback.register('wf_inventory:checkout', function(src, data)
    local inv = getInv(src); if not inv then return false end
    local shopId = openSecondary[src]
    local shopType = shopId and shopId:gsub('^shop:', '')
    local shop = shopType and WInv.Shops[shopType]
    if not shop then return false end
    if WAdmin and shopType == WAdmin.shopId and not WAdmin.isAdmin(src) then return false end
    if type(data) ~= 'table' or type(data.items) ~= 'table' or #data.items == 0 then return false end

    local total, lines = 0, {}
    for i = 1, #data.items do
        local line = data.items[i]
        local shopItem = line and shop.inventory[line.slot]
        if shopItem then
            local count = math.max(1, math.min(math.floor(tonumber(line.count) or 1), 500))
            total = total + (shopItem.price or 0) * count
            lines[#lines + 1] = { name = shopItem.name, count = count, metadata = shopItem.metadata }
        end
    end
    if #lines == 0 then return false end

    for i = 1, #lines do
        if not WInv.canCarryItem(inv, GetItemData(lines[i].name), lines[i].count, lines[i].metadata) then
            TriggerClientEvent('ox_inventory:notify', src, { type = 'error', description = 'Not enough space to carry that' })
            return { ok = false, reason = 'space' }
        end
    end

    local method = data.payment == 'bank' and 'bank' or 'cash'
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return false end

    if total > 0 then
        if method == 'bank' then
            if (player.PlayerData.money.bank or 0) < total then
                TriggerClientEvent('ox_inventory:notify', src, { type = 'error', description = 'Not enough on card' })
                return { ok = false, reason = 'funds' }
            end
            player.Functions.RemoveMoney('bank', total, 'w2f-inventory checkout')
        else
            if WInv.getItemCount(inv, 'money') < total then
                TriggerClientEvent('ox_inventory:notify', src, { type = 'error', description = 'Not enough cash' })
                return { ok = false, reason = 'funds' }
            end
            WInv.removeItem(inv, 'money', total, nil, nil, false, false)
        end
    end

    for i = 1, #lines do
        WInv.addItem(inv, lines[i].name, lines[i].count, lines[i].metadata)
    end

    local p2 = exports.qbx_core:GetPlayer(src)
    local cash = WInv.getItemCount(inv, 'money')
    local bank = p2 and p2.PlayerData.money.bank or 0
    TriggerClientEvent('ox_inventory:notify', src, { type = 'success', description = ('Purchase complete — $%d'):format(total) })
    return { ok = true, total = total, cash = cash, bank = bank }
end)

lib.callback.register('wf_inventory:craftItem', function(src, data)
    local id = openSecondary[src]
    if not id or not id:find('^crafting:') then return false end
    local benchId = id:gsub('^crafting:', '')
    local ok, err = WInv.craftRecipe(src, benchId, data.fromSlot)
    if not ok and err then
        local msg = err == 'missing_ingredients' and 'Missing materials' or 'Cannot carry that'
        TriggerClientEvent('ox_inventory:notify', src, { type = 'error', description = msg })
    end
    return ok or false
end)

RegisterNetEvent('inventory:server:OpenInventory', function(invType, name, data)
    local src = source
    if invType == 'shop' and name then
        WInv.registerShop(name, { name = name, label = name, inventory = data or {} })
        TriggerClientEvent('ox_inventory:forceOpenInventory', src, 'shop', { type = name, id = name })
    elseif invType == 'stash' and name then
        TriggerClientEvent('ox_inventory:forceOpenInventory', src, 'stash', { id = name })
    end
end)

lib.callback.register('wf_inventory:throwItem', function(src, data)
    local inv = getInv(src); if not inv then return false end
    local slot = inv.items[data.slot]; if not slot then return false end
    if IsAccountItem[slot.name] then return false end
    local count = math.min(tonumber(data.count) or 1, slot.count)
    local coords = data.coords
    if type(coords) ~= 'table' then
        local c = GetEntityCoords(GetPlayerPed(src)); coords = { x = c.x, y = c.y, z = c.z }
    end
    local def = GetItemData(slot.name)
    local model = (def.client and def.client.prop) or Config.dropModel
    local dropId = WInv.createDrop('drop', { { name = slot.name, count = count, metadata = slot.metadata } },
        vec3(coords.x, coords.y, coords.z), nil, nil, nil, model)
    if not dropId then return false end
    WInv.removeItem(inv, slot.name, count, slot.metadata, data.slot, false, true)
    return true
end)

RegisterNetEvent('wf_inventory:equip', function(slotId)
    local src = source
    WInv.currentWeapons[src] = slotId or nil
end)

RegisterNetEvent('ox_inventory:updateWeapon', function(action, value, slotId)
    local src = source
    local inv = getInv(src); if not inv then return end
    slotId = slotId or WInv.currentWeapons[src]
    local slot = inv.items[slotId]; if not slot then return end
    slot.metadata = slot.metadata or {}
    if action == 'ammo' then slot.metadata.ammo = value
    elseif action == 'durability' then slot.metadata.durability = value end
    WInv.syncInventory(inv)
    WInv.pushSlots(inv, { [slotId] = slotReturn(inv, slotId) })
end)
