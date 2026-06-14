local Inventories       = {}
local Drops             = {}
local RegisteredStashes = {}
local Shops             = {}
local Hooks             = { openInventory = {}, swapItems = {}, buyItem = {}, craftItem = {}, usingItem = {}, createItem = {} }
local hookId            = 0

local floor   = math.floor
local function round(n) return floor((tonumber(n) or 0) + 0.5) end

local function deepEqual(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for k, v in pairs(a) do if not deepEqual(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

local function assertMetadata(metadata)
    if metadata == nil then return nil end
    if type(metadata) == 'table' then return metadata end
    return { type = metadata }
end

local function metaMatches(slotMeta, queryMeta, strict)
    queryMeta = assertMetadata(queryMeta)
    if not queryMeta then return true end
    slotMeta = slotMeta or {}
    if strict then return deepEqual(slotMeta, queryMeta) end
    for k, v in pairs(queryMeta) do
        if not deepEqual(slotMeta[k], v) then return false end
    end
    return true
end

local function randomSerial()
    local t = {}
    for i = 1, 11 do
        local r = math.random(0, 35)
        t[i] = r < 10 and string.char(48 + r) or string.char(55 + r)
    end
    return table.concat(t)
end

local function defaultMetadata(def, metadata)
    metadata = assertMetadata(metadata) or {}
    if def.weapon then
        if metadata.durability == nil then metadata.durability = 100 end
        if metadata.components == nil then metadata.components = {} end
        if def.ammoname and metadata.ammo == nil then metadata.ammo = 0 end
        if (def.registerSerial or def.ammoname or def.throwable == nil) and metadata.serial == nil and not def.melee and not def.throwable then
            metadata.serial = randomSerial()
        end
    elseif def.degrade and metadata.durability == nil then
        metadata.durability = 100
    end
    return metadata
end

local function itemWeight(def, count, metadata)
    local base = (metadata and metadata.weight) or def.weight or 0
    return base * count
end

local function recalcWeight(inv)
    local w = 0
    for _, slot in pairs(inv.items) do
        local def = GetItemData(slot.name)
        w = w + itemWeight(def, slot.count, slot.metadata)
    end
    inv.weight = w
    return w
end

local function firstEmptySlot(inv)
    for i = 1, inv.slots do
        if not inv.items[i] then return i end
    end
    return nil
end

local function emptySlotCount(inv)
    local n = 0
    for i = 1, inv.slots do if not inv.items[i] then n = n + 1 end end
    return n
end

local function slotReturn(inv, slotId)
    local slot = inv.items[slotId]
    if not slot then return nil end
    local def = GetItemData(slot.name)
    return {
        name        = slot.name,
        label       = (slot.metadata and slot.metadata.label) or def.label,
        weight      = itemWeight(def, slot.count, slot.metadata),
        slot        = slotId,
        count       = slot.count,
        metadata    = slot.metadata or {},
        stack       = def.stack,
        close       = def.close,
        description = (slot.metadata and slot.metadata.description) or def.description,
    }
end

local function getInv(inv)
    if type(inv) == 'table' then
        if inv.items then return inv end
        inv = inv.id
    end
    return Inventories[inv]
end

local function Create(id, label, invType, slots, weight, maxWeight, owner, items)
    local self = {
        id = id, label = label or tostring(id), type = invType or 'stash',
        slots = slots or Config.playerSlots,
        maxWeight = maxWeight or Config.playerWeight,
        weight = weight or 0,
        owner = owner,
        items = items or {},
        open = false, changed = false, groups = nil,
    }
    Inventories[id] = self
    recalcWeight(self)
    return self
end

local syncInventory
local pushSlots
local saveInventory

local function getItemCount(inv, itemName, metadata, strict)
    inv = getInv(inv); if not inv then return 0 end
    local name = NormalizeItem(itemName); if not name then return 0 end
    local total = 0
    for _, slot in pairs(inv.items) do
        if slot.name == name and metaMatches(slot.metadata, metadata, strict) then
            total = total + slot.count
        end
    end
    return total
end

local function getItemSlots(inv, item, metadata, strict)
    inv = getInv(inv); if not inv then return nil end
    if strict == nil then strict = true end
    local name = type(item) == 'table' and item.name or NormalizeItem(item)
    local slots, total, empty = {}, 0, 0
    for i = 1, inv.slots do
        local slot = inv.items[i]
        if not slot then
            empty = empty + 1
        elseif slot.name == name and metaMatches(slot.metadata, metadata, strict) then
            slots[i] = slot.count
            total = total + slot.count
        end
    end
    return slots, total, empty
end

local function canCarryItem(inv, item, count, metadata)
    inv = getInv(inv); if not inv then return nil end
    local def = type(item) == 'table' and item or GetItemData(item)
    if not def then return false end
    count = count or 1
    if inv.weight + itemWeight(def, count, metadata) > inv.maxWeight then return false end
    if not def.stack then
        return emptySlotCount(inv) >= count
    end
    return true
end

local function addItem(inv, item, count, metadata, slot, cb)
    inv = getInv(inv)
    local function done(ok, resp)
        if cb then return cb(ok, resp) end
        return ok, resp
    end
    if not inv then return done(false, 'invalid_inventory') end
    if type(item) ~= 'string' and type(item) ~= 'table' then return done(false, 'invalid_item') end
    local def = type(item) == 'table' and item or GetItemData(item)
    if not def then return done(false, 'invalid_item') end
    count = round(count or 1)
    if count <= 0 then return done(false, 'invalid_count') end

    if not canCarryItem(inv, def, count, metadata) then return done(false, 'inventory_full') end

    local added = {}

    if def.stack then
        local am = assertMetadata(metadata)
        metadata = am and json.decode(json.encode(am)) or {}

        local targetSlot = slot
        if not targetSlot then
            for i = 1, inv.slots do
                local s = inv.items[i]
                if s and s.name == def.name and metaMatches(s.metadata, metadata, true) then
                    targetSlot = i; break
                end
            end
        end
        if not targetSlot or (inv.items[targetSlot] and inv.items[targetSlot].name ~= def.name) then
            targetSlot = firstEmptySlot(inv)
        end
        if not targetSlot then return done(false, 'inventory_full') end
        local s = inv.items[targetSlot]
        if s then s.count = s.count + count
        else inv.items[targetSlot] = { name = def.name, count = count, slot = targetSlot, metadata = metadata } end
        added[#added + 1] = slotReturn(inv, targetSlot)
    else

        for _ = 1, count do
            local empty = slot and not inv.items[slot] and slot or firstEmptySlot(inv)
            slot = nil
            if not empty then break end
            local md = defaultMetadata(def, metadata and assertMetadata(metadata) and json.decode(json.encode(metadata)) or nil)
            inv.items[empty] = { name = def.name, count = 1, slot = empty, metadata = md }
            added[#added + 1] = slotReturn(inv, empty)
        end
        if #added == 0 then return done(false, 'inventory_full') end
    end

    syncInventory(inv)
    local changes = {}
    for i = 1, #added do changes[added[i].slot] = added[i] end
    pushSlots(inv, changes)

    if inv.type == 'player' and Config.itemNotify and not def.ammo then
        TriggerClientEvent('ox_inventory:itemNotify', inv.id, { { label = def.label, name = def.name }, 'ui_added', count })
    end

    return done(true, #added == 1 and added[1] or added)
end

local function removeItem(inv, item, count, metadata, slot, ignoreTotal, strict)
    inv = getInv(inv); if not inv then return false, 'invalid_inventory' end
    local def = GetItemData(item); if not def then return false, 'invalid_item' end
    count = round(count or 1)
    if count <= 0 then return false, 'invalid_count' end
    if strict == nil then strict = true end

    local have = slot and (inv.items[slot] and inv.items[slot].name == def.name
        and metaMatches(inv.items[slot].metadata, metadata, strict) and inv.items[slot].count or 0)
        or getItemCount(inv, def.name, metadata, strict)

    if have < count then
        if not ignoreTotal then return false, 'not_enough_items' end
        count = have
    end
    if count <= 0 then return false, 'not_enough_items' end

    local remaining, changes = count, {}
    local order = {}
    if slot then order[1] = slot else
        for i = 1, inv.slots do order[#order + 1] = i end
    end
    for _, i in ipairs(order) do
        if remaining <= 0 then break end
        local s = inv.items[i]
        if s and s.name == def.name and metaMatches(s.metadata, metadata, strict) then
            local take = math.min(s.count, remaining)
            s.count = s.count - take
            remaining = remaining - take
            if s.count <= 0 then inv.items[i] = nil; changes[i] = false
            else changes[i] = slotReturn(inv, i) end
        end
    end

    syncInventory(inv)
    pushSlots(inv, changes)

    if inv.type == 'player' and Config.itemNotify and not def.ammo then
        TriggerClientEvent('ox_inventory:itemNotify', inv.id, { { label = def.label, name = def.name }, 'ui_removed', count })
    end
    return true
end

local function setItem(inv, item, count, metadata)
    inv = getInv(inv); if not inv then return false end
    local def = GetItemData(item); if not def then return false end
    count = round(count or 0)
    local current = getItemCount(inv, def.name, metadata, false)
    if count == current then return end
    if count > current then return addItem(inv, def.name, count - current, metadata)
    else return removeItem(inv, def.name, current - count, metadata, nil, true, false) end
end

local function getItem(inv, item, metadata, returnsCount)
    local def = GetItemData(item); if not def then return nil end
    local count = getItemCount(inv, def.name, metadata, false)
    if returnsCount then return count end
    local clone = {}
    for k, v in pairs(def) do clone[k] = v end
    clone.count = count
    return clone
end

local function getSlot(inv, slotId)
    inv = getInv(inv); if not inv or type(slotId) ~= 'number' then return nil end
    return slotReturn(inv, slotId)
end

local function getSlotWithItem(inv, itemName, metadata, strict)
    inv = getInv(inv); if not inv then return nil end
    local name = NormalizeItem(itemName)
    for i = 1, inv.slots do
        local s = inv.items[i]
        if s and s.name == name and metaMatches(s.metadata, metadata, strict) then
            return slotReturn(inv, i)
        end
    end
    return nil
end

local function getSlotsWithItem(inv, itemName, metadata, strict)
    inv = getInv(inv); if not inv then return nil end
    local name = NormalizeItem(itemName)
    local out = {}
    for i = 1, inv.slots do
        local s = inv.items[i]
        if s and s.name == name and metaMatches(s.metadata, metadata, strict) then
            out[#out + 1] = slotReturn(inv, i)
        end
    end
    return out
end

local function getSlotIdWithItem(inv, itemName, metadata, strict)
    local s = getSlotWithItem(inv, itemName, metadata, strict)
    return s and s.slot or nil
end

local function getSlotIdsWithItem(inv, itemName, metadata, strict)
    local slots = getSlotsWithItem(inv, itemName, metadata, strict)
    if not slots then return nil end
    local ids = {}
    for i = 1, #slots do ids[i] = slots[i].slot end
    return ids
end

local function getEmptySlot(inv) inv = getInv(inv); return inv and firstEmptySlot(inv) or nil end

local function getSlotForItem(inv, itemName, metadata)
    inv = getInv(inv); if not inv then return nil end
    local name = NormalizeItem(itemName)
    local def = GetItemData(name)
    if def and def.stack then
        for i = 1, inv.slots do
            local s = inv.items[i]
            if s and s.name == name and metaMatches(s.metadata, metadata, true) then return i end
        end
    end
    return firstEmptySlot(inv)
end

local function searchItems(inv, search, items, metadata)
    inv = getInv(inv); if not inv then return false end
    if search == 'slots' then search = 1 elseif search == 'count' then search = 2 end

    local single = type(items) == 'string' or (type(items) == 'table' and #items == 1)
    local list = type(items) == 'string' and { items } or items
    if type(list) ~= 'table' then return false end

    local result = {}
    local anyFound = false
    for _, raw in ipairs(list) do
        local name = NormalizeItem(raw)
        local matchSlots, matchCount = {}, 0
        for i = 1, inv.slots do
            local s = inv.items[i]
            if s and s.name == name and metaMatches(s.metadata, metadata, false) then
                matchSlots[#matchSlots + 1] = slotReturn(inv, i)
                matchCount = matchCount + s.count
            end
        end
        if matchCount > 0 then anyFound = true end
        if search == 1 then result[name] = matchSlots
        else result[name] = matchCount end
    end

    if not anyFound and search == 1 then

        if single then return false end
    end

    if single then
        local v = result[NormalizeItem(type(items) == 'string' and items or items[1])]
        if search == 1 then
            if not v or #v == 0 then return false end
            return v
        else
            return v or 0
        end
    end
    return result
end

local accountCounts

pushSlots = function(inv, changes)
    if inv.type == 'player' then
        TriggerClientEvent('wf_inventory:sync', inv.id, changes, inv.weight, inv.id)
    end

    if inv.open and type(inv.open) == 'number' and inv.open ~= inv.id then
        TriggerClientEvent('wf_inventory:syncSecondary', inv.open, inv.id, changes, inv.weight)
    end
end

local moneySync
syncInventory = function(inv)
    recalcWeight(inv)
    inv.changed = true
    if inv.type == 'player' then moneySync(inv) end
end

saveInventory = function(inv) end

accountCounts = function(inv)
    local counts = {}
    for _, slot in pairs(inv.items) do
        if IsAccountItem[slot.name] then
            counts[slot.name] = (counts[slot.name] or 0) + slot.count
        end
    end
    return counts
end

local applyingMoney = {}

moneySync = function(inv)
    local src = inv.id
    if type(src) ~= 'number' or applyingMoney[src] then return end
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local counts = accountCounts(inv)
    for account in pairs(IsAccountItem) do
        local moneyType = AccountMoneyType[account] or account
        local itemCount = counts[account] or 0
        local current = player.PlayerData.money[moneyType]
        if current ~= nil and current ~= itemCount then
            player.Functions.SetMoney(moneyType, itemCount, 'w2f-inventory sync')
        end
    end
end

local function applyMoneyFromFramework(src, account, amount)
    local inv = Inventories[src]; if not inv then return end
    applyingMoney[src] = true
    setItem(inv, account, amount)
    applyingMoney[src] = nil
end

local function loadPlayerRow(citizenid, cb)
    MySQL.scalar('SELECT inventory FROM players WHERE citizenid = ?', { citizenid }, function(data)
        if not data then return cb({}) end
        local ok, decoded = pcall(json.decode, data)
        cb(ok and type(decoded) == 'table' and decoded or {})
    end)
end

saveInventory = function(inv)
    if not inv or not inv.changed then return end
    if inv.type == 'player' and inv.owner then
        local out = {}
        for slotId, slot in pairs(inv.items) do
            if not IsAccountItem[slot.name] then
                out[#out + 1] = { name = slot.name, count = slot.count, slot = slotId, metadata = slot.metadata }
            end
        end
        MySQL.update('UPDATE players SET inventory = ? WHERE citizenid = ?', { json.encode(out), inv.owner })
        inv.changed = false
    elseif inv.type == 'stash' then
        local out = {}
        for slotId, slot in pairs(inv.items) do
            if not IsAccountItem[slot.name] then
                out[#out + 1] = { name = slot.name, count = slot.count, slot = slotId, metadata = slot.metadata }
            end
        end
        MySQL.update('INSERT INTO w2f_stashes (name, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = ?',
            { inv.id, json.encode(out), json.encode(out) })
        inv.changed = false
    end
end

local function buildItemsFromRows(rows)
    local items = {}
    for i = 1, #rows do
        local row = rows[i]
        local def = GetItemData(row.name)
        if def and type(row.slot) == 'number' and row.slot >= 1 and row.count and row.count > 0 then
            items[row.slot] = {
                name = def.name, count = round(row.count), slot = row.slot,
                metadata = type(row.metadata) == 'table' and row.metadata or (row.info) or {},
            }
        end
    end
    return items
end

local Loading = {}
local function setupPlayer(playerData)
    local src = playerData.source
    if not src or Inventories[src] or Loading[src] then return end
    Loading[src] = true
    local citizenid = playerData.citizenid or playerData.identifier
    loadPlayerRow(citizenid, function(rows)
        local items = buildItemsFromRows(rows)
        local inv = Create(src, playerData.name, 'player', Config.playerSlots, 0, Config.playerWeight, citizenid, items)
        local overflow = {}
        for slotId in pairs(inv.items) do
            if slotId > inv.slots then overflow[#overflow + 1] = slotId end
        end
        for i = 1, #overflow do
            local slot = inv.items[overflow[i]]
            inv.items[overflow[i]] = nil
            local free = firstEmptySlot(inv)
            if free then slot.slot = free; inv.items[free] = slot end
        end
        inv.player = { source = src, name = playerData.name, groups = playerData.groups }

        applyingMoney[src] = true
        for account in pairs(IsAccountItem) do
            local moneyType = AccountMoneyType[account] or account
            local amount = playerData.money and playerData.money[moneyType]
            if amount ~= nil then setItem(inv, account, amount) end
        end
        applyingMoney[src] = nil
        recalcWeight(inv)

        local list = {}
        for slotId, slot in pairs(inv.items) do list[slotId] = slotReturn(inv, slotId) end
        TriggerClientEvent('ox_inventory:setPlayerInventory', src, Drops, list, inv.weight, inv.player)
        Loading[src] = nil
    end)
end

local function gatherPlayerData(src)
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return nil end
    local pd = player.PlayerData
    local groups = {}
    if pd.job then groups[pd.job.name] = pd.job.grade and pd.job.grade.level or 0 end
    if pd.gang then groups[pd.gang.name] = pd.gang.grade and pd.gang.grade.level or 0 end
    return {
        source = src,
        citizenid = pd.citizenid,
        identifier = pd.citizenid,
        name = ('%s %s'):format(pd.charinfo.firstname, pd.charinfo.lastname),
        money = pd.money,
        groups = groups,
    }
end

RegisterNetEvent('QBCore:Server:PlayerLoaded', function(player)
    local src = type(player) == 'table' and (player.PlayerData and player.PlayerData.source or player.source) or source
    if not src then return end
    local data = gatherPlayerData(src)
    if data then setupPlayer(data) end
end)

AddStateBagChangeHandler('loadInventory', nil, function(bagName, _, value)
    if not value then return end
    local src = tonumber(bagName:gsub('player:', ''))
    if not src or Inventories[src] then return end
    SetTimeout(0, function()
        local data = gatherPlayerData(src)
        if data then setupPlayer(data) end
    end)
end)

local function playerDropped(src)
    Loading[src] = nil
    if WInv then WInv.currentWeapons[src] = nil end
    local inv = Inventories[src]
    if not inv then return end
    saveInventory(inv)
    Inventories[src] = nil
    applyingMoney[src] = nil
end
AddEventHandler('qbx_core:server:playerLoggedOut', playerDropped)
AddEventHandler('playerDropped', function() playerDropped(source) end)

AddEventHandler('qbx_core:server:onGroupUpdate', function(src, groupName, grade)
    local inv = Inventories[src]
    if inv and inv.player then
        inv.player.groups = inv.player.groups or {}
        inv.player.groups[groupName] = grade
    end
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= CurrentResource then return end

    MySQL.query([[CREATE TABLE IF NOT EXISTS w2f_stashes (name VARCHAR(100) NOT NULL, data LONGTEXT, PRIMARY KEY (name))]])
    MySQL.query([[ALTER TABLE players ADD COLUMN IF NOT EXISTS inventory LONGTEXT]])
    SetTimeout(1000, function()
        local players = exports.qbx_core:GetQBPlayers()
        for src in pairs(players or {}) do
            local data = gatherPlayerData(tonumber(src) or src)
            if data then setupPlayer(data) end
        end
    end)
end)

local function saveAll()
    for _, inv in pairs(Inventories) do saveInventory(inv) end
end
AddEventHandler('onResourceStop', function(res) if res == CurrentResource then saveAll() end end)
AddEventHandler('txAdmin:events:scheduledRestart', function(e) if e and e.secondsRemaining == 60 then saveAll() end end)

CreateThread(function()
    while true do
        Wait(300000)
        saveAll()
    end
end)

local function registerStash(name, label, slots, maxWeight, owner, groups, coords)
    RegisteredStashes[name] = {
        name = name, label = label or name,
        slots = tonumber(slots) or 50,
        maxWeight = tonumber(maxWeight) or 100000,
        owner = owner, groups = groups, coords = coords,
    }
    local inv = Inventories[name]
    if inv then
        inv.slots = RegisteredStashes[name].slots
        inv.maxWeight = RegisteredStashes[name].maxWeight
        inv.groups = groups
    end
end

local function loadStash(stashId, def)
    if Inventories[stashId] then return Inventories[stashId] end
    local inv = Create(stashId, def.label, 'stash', def.slots, 0, def.maxWeight, def.owner, {})
    inv.groups = def.groups
    return inv
end

local function resolveStash(stashId, owner)
    local base = stashId
    local def = RegisteredStashes[base]
    if not def then return nil end
    local realId = base
    if def.owner == true and owner then realId = base .. ':' .. owner end
    local inv = Inventories[realId]
    if inv then return inv end
    inv = loadStash(realId, def)
    inv.owner = (def.owner == true) and owner or def.owner

    local ok, data = pcall(function()
        return MySQL.scalar.await('SELECT data FROM w2f_stashes WHERE name = ?', { realId })
    end)
    if ok and data then
        local decoded, rows = pcall(json.decode, data)
        if decoded and type(rows) == 'table' then
            inv.items = buildItemsFromRows(rows)
            recalcWeight(inv)
        end
    end
    return inv
end

local function createTemporaryStash(properties)
    properties = properties or {}
    hookId = hookId + 1
    local id = ('temp-%d'):format(hookId)
    local inv = Create(id, properties.label or 'Container', 'temp', properties.slots or 50, 0, properties.maxWeight or 100000, nil, {})
    inv.groups = properties.groups
    if properties.items then
        for i = 1, #properties.items do
            local it = properties.items[i]
            addItem(inv, it.name or it[1], it.count or it[2] or 1, it.metadata)
        end
    end
    return id
end

local dropCounter = 0
local function createDrop(prefix, items, coords, slots, maxWeight, instance, model)
    dropCounter = dropCounter + 1
    local id = ('%s-%06d'):format(prefix or 'drop', dropCounter)
    local inv = Create(id, 'Drop', 'drop', slots or Config.dropSlots, 0, maxWeight or Config.dropWeight, nil, {})
    if items then
        for i = 1, #items do
            local it = items[i]
            if it.name then addItem(inv, it.name, it.count or 1, it.metadata, it.slot) end
        end
    end
    Drops[id] = { coords = coords, instance = instance, model = model or Config.dropModel }
    TriggerClientEvent('ox_inventory:createDrop', -1, id, { coords = coords, instance = instance }, false, model or Config.dropModel)
    return id
end

local function customDrop(prefix, items, coords, slots, maxWeight, instance, model)
    return createDrop(prefix or 'drop', items, coords, slots, maxWeight, instance, model)
end

local function createDropFromPlayer(playerId)
    local inv = Inventories[playerId]; if not inv then return end
    local items = {}
    for _, slot in pairs(inv.items) do
        if not IsAccountItem[slot.name] then
            items[#items + 1] = { name = slot.name, count = slot.count, metadata = slot.metadata }
        end
    end
    if #items == 0 then return end
    local ped = GetPlayerPed(playerId)
    local coords = GetEntityCoords(ped)

    for slotId, slot in pairs(inv.items) do
        if not IsAccountItem[slot.name] then inv.items[slotId] = nil end
    end
    syncInventory(inv)
    local list = {}
    for slotId in pairs(inv.items) do list[slotId] = slotReturn(inv, slotId) end
    TriggerClientEvent('ox_inventory:setPlayerInventory', playerId, Drops, list, inv.weight, inv.player)
    return createDrop('drop', items, vec3(coords.x, coords.y, coords.z))
end

local function removeInventory(inv)
    inv = getInv(inv); if not inv then return end
    saveInventory(inv)
    if inv.type == 'drop' then
        Drops[inv.id] = nil
        TriggerClientEvent('ox_inventory:removeDrop', -1, inv.id)
    end
    Inventories[inv.id] = nil
end

local function registerShop(shopType, details)
    Shops[shopType] = details
    local inventory = details.inventory or details.items or {}
    for i = 1, #inventory do
        local it = inventory[i]
        it.slot = i
        it.metadata = it.metadata or {}
        local def = GetItemData(it.name)
        it.weight = def and def.weight or 0
    end
    details.inventory = inventory
end

local function loadLua(path)
    local content = LoadResourceFile(CurrentResource, path)
    if not content then return {} end
    local fn = load(content, ('@@%s/%s'):format(CurrentResource, path))
    if not fn then return {} end
    local ok, res = pcall(fn)
    return ok and type(res) == 'table' and res or {}
end
local CraftingBenches = loadLua('data/crafting.lua')
local ShopsData = loadLua('data/shops.lua')
for shopType, shop in pairs(ShopsData) do registerShop(shopType, shop) end

local function craftRecipe(src, benchId, recipeIndex)
    local bench = CraftingBenches[benchId]; if not bench then return false end
    local recipe = bench.recipes[recipeIndex]; if not recipe then return false end
    local inv = Inventories[src]; if not inv then return false end
    for item, need in pairs(recipe.ingredients) do
        if getItemCount(inv, item) < need then return false, 'missing_ingredients' end
    end
    if not canCarryItem(inv, GetItemData(recipe.name), recipe.count or 1) then return false, 'cannot_carry' end
    for item, need in pairs(recipe.ingredients) do
        removeItem(inv, item, need, nil, nil, false, false)
    end
    addItem(inv, recipe.name, recipe.count or 1)
    return true
end

local function clearInventory(inv, keep)
    inv = getInv(inv); if not inv then return end
    local keepSet = {}
    if type(keep) == 'string' then keepSet[NormalizeItem(keep)] = true
    elseif type(keep) == 'table' then for i = 1, #keep do keepSet[NormalizeItem(keep[i])] = true end end
    local changes = {}
    for slotId, slot in pairs(inv.items) do
        if not keepSet[slot.name] then inv.items[slotId] = nil; changes[slotId] = false end
    end
    syncInventory(inv)
    pushSlots(inv, changes)
    if inv.type == 'player' then
        local list = {}
        for slotId in pairs(inv.items) do list[slotId] = slotReturn(inv, slotId) end
        TriggerClientEvent('ox_inventory:setPlayerInventory', inv.id, Drops, list, inv.weight, inv.player)
    end
end

local function confiscateInventory(src)
    local inv = Inventories[src]; if not inv then return end
    local out = {}
    for slotId, slot in pairs(inv.items) do
        if not IsAccountItem[slot.name] then
            out[#out + 1] = { name = slot.name, count = slot.count, slot = slotId, metadata = slot.metadata }
        end
    end
    MySQL.update('INSERT INTO w2f_stashes (name, data) VALUES (?, ?) ON DUPLICATE KEY UPDATE data = ?',
        { 'confiscate:' .. inv.owner, json.encode(out), json.encode(out) })
    local keep = {}
    for a in pairs(IsAccountItem) do keep[#keep + 1] = a end
    clearInventory(inv, keep)
    TriggerClientEvent('ox_inventory:inventoryConfiscated', src)
end

local function returnInventory(src)
    local inv = Inventories[src]; if not inv then return end
    MySQL.scalar('SELECT data FROM w2f_stashes WHERE name = ?', { 'confiscate:' .. inv.owner }, function(data)
        if not data then return end
        local ok, rows = pcall(json.decode, data)
        if ok and type(rows) == 'table' then
            for i = 1, #rows do addItem(inv, rows[i].name, rows[i].count, rows[i].metadata, rows[i].slot) end
        end
        MySQL.update('DELETE FROM w2f_stashes WHERE name = ?', { 'confiscate:' .. inv.owner })
        TriggerClientEvent('ox_inventory:inventoryReturned', src)
    end)
end

local currentWeapons = {}

local function getCurrentWeapon(src)
    local slotId = currentWeapons[src]
    local inv = Inventories[src]
    if not slotId or not inv then return nil end
    local slot = inv.items[slotId]
    local def = slot and GetItemData(slot.name)
    if not def or not def.weapon then currentWeapons[src] = nil; return nil end
    return slotReturn(inv, slotId)
end

local function registerHookFn(event, cb, options)
    if not Hooks[event] then Hooks[event] = {} end
    hookId = hookId + 1
    local id = hookId
    Hooks[event][id] = { cb = cb, options = options or {}, resource = GetInvokingResource() }
    return id
end

local function triggerHooks(event, payload)
    local list = Hooks[event]
    if not list then return true end
    for _, hook in pairs(list) do
        local f = hook.options.inventoryFilter
        local pass = true
        if f and payload.inventoryId then
            pass = false
            for i = 1, #f do
                if tostring(payload.inventoryId):find(f[i]) then pass = true; break end
            end
        end
        if pass then
            local ok, result = pcall(type(hook.cb) == 'function' and hook.cb or hook.cb.__call, payload)
            if ok and result == false then return false end
            if ok and type(result) == 'table' then payload.returned = result end
        end
    end
    return true
end

local function removeHooksFn(id)
    local res = GetInvokingResource()
    for _, list in pairs(Hooks) do
        for hid, hook in pairs(list) do
            if (id and hid == id) or (not id and hook.resource == res) then list[hid] = nil end
        end
    end
end

exports('AddItem', addItem)
exports('RemoveItem', removeItem)
exports('SetItem', function(inv, item, count, metadata)

    if type(inv) == 'number' and IsAccountItem[NormalizeItem(item) or ''] then
        return applyMoneyFromFramework(inv, NormalizeItem(item), count)
    end
    return setItem(inv, item, count, metadata)
end)
exports('GetItem', getItem)
exports('GetItemCount', getItemCount)
exports('Search', searchItems)
exports('GetItemSlots', getItemSlots)
exports('GetSlot', getSlot)
exports('GetSlotWithItem', getSlotWithItem)
exports('GetSlotIdWithItem', getSlotIdWithItem)
exports('GetSlotsWithItem', getSlotsWithItem)
exports('GetSlotIdsWithItem', getSlotIdsWithItem)
exports('GetEmptySlot', getEmptySlot)
exports('GetSlotForItem', getSlotForItem)
exports('CanCarryItem', canCarryItem)
exports('CanCarryAmount', function(inv, item)
    inv = getInv(inv); if not inv then return nil end
    local def = type(item) == 'table' and item or GetItemData(item)
    if not def or not def.weight or def.weight <= 0 then return inv and inv.slots or 0 end
    return floor((inv.maxWeight - inv.weight) / def.weight)
end)
exports('CanCarryWeight', function(inv, weight)
    inv = getInv(inv); if not inv then return false, 0 end
    local available = inv.maxWeight - inv.weight
    return weight <= available, available
end)
exports('GetInventory', function(inv, owner)
    if inv == nil then return nil end
    if owner and RegisteredStashes[inv] then return resolveStash(inv, owner) end
    return getInv(inv)
end)
exports('Inventory', function(inv, owner)
    if inv == nil then return nil end
    if owner and RegisteredStashes[inv] then return resolveStash(inv, owner) end
    return getInv(inv)
end)
exports('GetInventoryItems', function(inv, owner)
    local i = owner and resolveStash(inv, owner) or getInv(inv)
    return i and i.items or nil
end)
exports('SetMetadata', function(inv, slotId, metadata)
    inv = getInv(inv); if not inv or type(slotId) ~= 'number' then return end
    local slot = inv.items[slotId]; if not slot then return end
    slot.metadata = assertMetadata(metadata) or {}
    syncInventory(inv)
    pushSlots(inv, { [slotId] = slotReturn(inv, slotId) })
end)
exports('SetDurability', function(inv, slotId, durability)
    inv = getInv(inv); if not inv or type(slotId) ~= 'number' or type(durability) ~= 'number' then return end
    local slot = inv.items[slotId]; if not slot then return end
    slot.metadata = slot.metadata or {}
    slot.metadata.durability = durability
    syncInventory(inv)
    pushSlots(inv, { [slotId] = slotReturn(inv, slotId) })
end)
exports('SetMaxWeight', function(inv, maxWeight)
    inv = getInv(inv); if not inv then return end
    inv.maxWeight = maxWeight
    if inv.type == 'player' then TriggerClientEvent('ox_inventory:refreshMaxWeight', inv.id, maxWeight) end
end)
local function setSlotCount(inv, slotId, count)
    inv = getInv(inv); if not inv then return end
    local slot = inv.items[slotId]
    if not slot then return end
    count = round(count)
    if count <= 0 then inv.items[slotId] = nil else slot.count = count end
    syncInventory(inv)
    pushSlots(inv, { [slotId] = inv.items[slotId] and slotReturn(inv, slotId) or false })
end
exports('SetSlot', setSlotCount)
exports('SetSlotCount', setSlotCount)
exports('ClearInventory', clearInventory)
exports('ConfiscateInventory', confiscateInventory)
exports('ReturnInventory', returnInventory)
exports('RemoveInventory', removeInventory)
exports('RegisterStash', registerStash)
exports('CreateTemporaryStash', createTemporaryStash)
exports('RegisterShop', registerShop)
exports('CustomDrop', customDrop)
exports('CreateDropFromPlayer', createDropFromPlayer)
exports('GetCurrentWeapon', getCurrentWeapon)
exports('registerHook', registerHookFn)
exports('removeHooks', removeHooksFn)
exports('setPlayerInventory', function(player, data) setupPlayer(player) end)

exports('forceOpenInventory', function(playerId, invType, data)
    TriggerClientEvent('ox_inventory:forceOpenInventory', playerId, invType, data)
end)
exports('InspectInventory', function(playerId, invId)
    local target = getInv(invId)
    if target then
        local list = {}
        for slotId in pairs(target.items) do list[slotId] = slotReturn(target, slotId) end
        TriggerClientEvent('ox_inventory:viewInventory', playerId, target.id, list, target.weight, target.maxWeight, target.slots, target.label)
    end
end)
exports('UpdateVehicle', function(oldPlate, newPlate) end)
exports('GetContainerFromSlot', function(inv, slotId) return nil end)
exports('setContainerProperties', function(item, properties) end)
exports('ConvertItems', function() end)

exports('addCash', function() end)
exports('removeCash', function() end)
exports('getCash', function(src) local p = exports.qbx_core:GetPlayer(src); return p and p.PlayerData.money.cash or 0 end)
exports('getBank', function(src) local p = exports.qbx_core:GetPlayer(src); return p and p.PlayerData.money.bank or 0 end)
exports('giveCard', function() end)
exports('getCards', function() return {} end)
exports('displayMetadata', function() end)
exports('suppressItemNotifications', function() end)

AddEventHandler('ox_inventory:customDrop', function(prefix, items, coords, slots, maxWeight, instance, model)
    customDrop(prefix, items, coords, slots, maxWeight, instance, model)
end)
RegisterNetEvent('ox_inventory:setPlayerInventory', function() setupPlayer(gatherPlayerData(source)) end)

WInv = {
    Inventories = Inventories, Drops = Drops, RegisteredStashes = RegisteredStashes, Shops = Shops,
    getInv = getInv, addItem = addItem, removeItem = removeItem, slotReturn = slotReturn,
    resolveStash = resolveStash, syncInventory = syncInventory, pushSlots = pushSlots,
    recalcWeight = recalcWeight, getItemCount = getItemCount, triggerHooks = triggerHooks,
    currentWeapons = currentWeapons, firstEmptySlot = firstEmptySlot, canCarryItem = canCarryItem,
    Shops = Shops, registerShop = registerShop, getCurrentWeapon = getCurrentWeapon,
    CraftingBenches = CraftingBenches, craftRecipe = craftRecipe, createDrop = createDrop,
}
