local PlayerData = { inventory = {}, weight = 0, maxWeight = Config.playerWeight, loaded = false, groups = {} }
local uiReady = false
local invOpen = false
local currentWeapon = nil
local secondaryOpen = nil
local stashTarget = nil
local spawnDrop, removeDropProp, throwItemFn

local function ped() return PlayerPedId() end

local function nui(action, data) SendNUIMessage({ action = action, data = data }) end

local function sendMoney()
    local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
    if ok and pd and pd.money then
        nui('money', { cash = pd.money.cash or 0, bank = pd.money.bank or 0 })
    end
end
RegisterNetEvent('QBCore:Client:OnMoneyChange', function() if invOpen then sendMoney() end end)

local function slotList(items)

    return items or {}
end

local function sendInit()
    if not uiReady or not PlayerData.loaded then return end
    nui('init', {
        items = BuildItemCatalog(),
        imagepath = Config.imagePath,
        leftInventory = {
            id = cache and cache.serverId or GetPlayerServerId(PlayerId()),
            slots = Config.playerSlots,
            items = PlayerData.inventory,
            maxWeight = PlayerData.maxWeight,
        },
    })
end

RegisterNetEvent('ox_inventory:setPlayerInventory', function(drops, items, weight, player)
    PlayerData.inventory = items or {}
    PlayerData.weight = weight or 0
    PlayerData.maxWeight = Config.playerWeight
    if player then PlayerData.groups = player.groups or {} end
    PlayerData.loaded = true
    TriggerEvent('ox_inventory:updateInventory', PlayerData.inventory)
    sendInit()
    if drops and spawnDrop then for id, info in pairs(drops) do spawnDrop(id, info) end end
end)

local function fireItemCounts(changes)
    local counted = {}
    for _, item in pairs(changes) do
        if item and item.name and not counted[item.name] then
            counted[item.name] = true
            local total = 0
            for _, s in pairs(PlayerData.inventory) do if s.name == item.name then total = total + s.count end end
            TriggerEvent('ox_inventory:itemCount', item.name, total)
        end
    end
end

RegisterNetEvent('wf_inventory:sync', function(changes, weight, invId)
    for slotId, item in pairs(changes) do
        PlayerData.inventory[slotId] = item or nil
    end
    PlayerData.weight = weight or PlayerData.weight

    local payload = {}
    for slotId, item in pairs(changes) do
        payload[#payload + 1] = { item = item or { slot = slotId }, inventory = 'player' }
    end
    nui('refreshSlots', { items = payload })
    TriggerEvent('ox_inventory:updateInventory', changes)
    fireItemCounts(changes)
end)

RegisterNetEvent('wf_inventory:syncSecondary', function(invId, changes, weight)
    local payload = {}
    for slotId, item in pairs(changes) do
        payload[#payload + 1] = { item = item or { slot = slotId }, inventory = invId }
    end
    nui('refreshSlots', { items = payload })
end)

local function rightGround()
    return { id = 'newdrop', type = 'newdrop', slots = Config.dropSlots, maxWeight = Config.dropWeight, label = 'Ground', items = {} }
end

local function doOpenUI(rightInv)
    if not PlayerData.loaded then return end
    invOpen = true
    LocalPlayer.state:set('invOpen', true, false)
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    nui('setupInventory', {
        leftInventory = {
            id = cache.serverId, type = 'player', slots = Config.playerSlots,
            maxWeight = PlayerData.maxWeight, items = PlayerData.inventory, label = 'Pockets',
        },
        rightInventory = rightInv or rightGround(),
    })
    sendMoney()
end

local function openInventory(invType, data)
    if invOpen then return end
    if not invType or invType == 'player' then
        if type(invType) == 'number' or (type(data) == 'number') then

            local serverId = type(invType) == 'number' and invType or data
            local payload = lib.callback.await('wf_inventory:open', false, 'drop', serverId)
            if payload then secondaryOpen = payload.id; return doOpenUI(payload) end
            return
        end
        return doOpenUI(nil)
    end
    local payload = lib.callback.await('wf_inventory:open', false, invType, data)
    if not payload then
        lib.notify({ type = 'error', description = 'Can\'t access that' })
        return
    end
    secondaryOpen = payload.id
    doOpenUI({
        id = payload.id, type = payload.type, slots = payload.slots,
        maxWeight = payload.maxWeight, items = payload.items, label = payload.label,
    })
end
exports('openInventory', openInventory)
RegisterNetEvent('ox_inventory:openInventory', function(left, right) openInventory(left, right) end)
RegisterNetEvent('ox_inventory:forceOpenInventory', function(invType, data) openInventory(invType, data) end)

local function closeInventory(server)
    if not invOpen then return end
    invOpen = false
    LocalPlayer.state:set('invOpen', false, false)
    SetNuiFocus(false, false)
    nui('closeInventory', {})
    if secondaryOpen then
        lib.callback.await('wf_inventory:close', false)
        secondaryOpen = nil
    end
end
exports('closeInventory', closeInventory)
RegisterNetEvent('ox_inventory:closeInventory', function() closeInventory(true) end)

local function openNearbyInventory()
    openInventory('drop', nil)
end
exports('openNearbyInventory', openNearbyInventory)

RegisterCommand('+w2finv', function()
    if invOpen then closeInventory() else openInventory('player') end
end, false)
RegisterCommand('-w2finv', function() end, false)
RegisterKeyMapping('+w2finv', 'Open inventory', 'keyboard', Config.keys[1] or 'TAB')

local function equipWeapon(slotId)
    local item = PlayerData.inventory[slotId]; if not item then return end
    local hash = joaat(item.name)
    local ammo = (item.metadata and item.metadata.ammo) or 0
    if currentWeapon and currentWeapon.hash == hash then
        TriggerServerEvent('ox_inventory:updateWeapon', 'ammo', GetAmmoInPedWeapon(ped(), hash), currentWeapon.slot)
        RemoveWeaponFromPed(ped(), hash); currentWeapon = nil
        TriggerEvent('ox_inventory:currentWeapon', nil)
        TriggerServerEvent('wf_inventory:equip', false)
        return
    end
    if currentWeapon then
        TriggerServerEvent('ox_inventory:updateWeapon', 'ammo', GetAmmoInPedWeapon(ped(), currentWeapon.hash), currentWeapon.slot)
        RemoveWeaponFromPed(ped(), currentWeapon.hash)
    end
    GiveWeaponToPed(ped(), hash, ammo, false, true)
    SetCurrentPedWeapon(ped(), hash, true)
    SetPedAmmo(ped(), hash, ammo)
    currentWeapon = { slot = slotId, name = item.name, hash = hash, metadata = item.metadata, ammo = ammo }
    TriggerEvent('ox_inventory:currentWeapon', currentWeapon)
    TriggerServerEvent('wf_inventory:equip', slotId)
end

local function disarm(noAnim)
    if not currentWeapon then return end
    TriggerServerEvent('ox_inventory:updateWeapon', 'ammo', GetAmmoInPedWeapon(ped(), currentWeapon.hash), currentWeapon.slot)
    RemoveWeaponFromPed(ped(), currentWeapon.hash)
    currentWeapon = nil
    TriggerEvent('ox_inventory:currentWeapon', nil)
    TriggerServerEvent('wf_inventory:equip', false)
end
exports('disarm', disarm)
RegisterNetEvent('ox_inventory:disarm', function(noAnim) disarm(noAnim) end)

local usingItem = false
local function useSlot(slotId, noAnim)
    if usingItem then return end
    local item = PlayerData.inventory[slotId]; if not item then return end
    local def = GetItemData(item.name); if not def then return end

    if def.weapon then
        equipWeapon(slotId)
        return
    end

    usingItem = true
    local res = lib.callback.await('wf_inventory:useItem', false, slotId)
    if type(res) == 'table' then
        if res.fallback then
            local ok = lib.progressBar({
                duration = res.usetime or 2500,
                label = ('Using %s'):format(res.label or item.name),
                useWhileDead = false, canCancel = true,
                disable = { car = true, combat = true },
            })
            if ok then lib.callback.await('wf_inventory:useFallback', false, slotId) end
        end
        if res.clientEvent then
            TriggerEvent(res.clientEvent, { name = item.name, slot = slotId, metadata = item.metadata })
        end
    end
    usingItem = false
end
exports('useSlot', useSlot)
exports('useItem', function(data, cb) if type(data) == 'number' then useSlot(data) elseif type(data) == 'table' and data.slot then useSlot(data.slot) end if cb then cb() end end)
RegisterNetEvent('ox_inventory:item', function(data) if data and data.slot then useSlot(data.slot) end end)

local function giveItemToTarget(serverId, slotId, count)
    if type(slotId) ~= 'number' then error('slotId must be a number') end
    lib.callback.await('wf_inventory:giveItem', false, { slot = slotId, count = count or 0, target = serverId })
end
exports('giveItemToTarget', giveItemToTarget)

RegisterNUICallback('uiLoaded', function(_, cb) uiReady = true; sendInit(); cb(1) end)

RegisterNUICallback('exit', function(_, cb) closeInventory(); cb(1) end)

RegisterNUICallback('useItem', function(slot, cb) cb(1); if type(slot) == 'number' then useSlot(slot) end end)

RegisterNUICallback('giveItem', function(data, cb)
    cb(1)
    if data and data.slot then
        lib.callback.await('wf_inventory:giveItem', false, { slot = data.slot, count = data.count })
    end
end)

RegisterNUICallback('swapItems', function(data, cb)
    local ok = lib.callback.await('wf_inventory:swap', false, data)
    cb(ok or false)
end)

RegisterNUICallback('buyItem', function(data, cb)
    local ok = lib.callback.await('wf_inventory:buyItem', false, data)
    cb(ok or false)
end)

RegisterNUICallback('checkout', function(data, cb)
    local res = lib.callback.await('wf_inventory:checkout', false, data)
    cb(res or false)
end)

RegisterNUICallback('craftItem', function(data, cb)
    if data.duration and data.duration > 0 then
        local ok = lib.progressBar({ duration = data.duration, label = 'Crafting',
            canCancel = true, disable = { move = true, combat = true, car = true } })
        if not ok then return cb(false) end
    end
    local ok = lib.callback.await('wf_inventory:craftItem', false, data)
    cb(ok or false)
end)

RegisterNUICallback('throwItem', function(data, cb)
    cb(1)
    if data and data.slot then throwItemFn(data.slot, data.count) end
end)

local function localCount(itemName, metadata, strict)
    local name = NormalizeItem(itemName); local n = 0
    for _, s in pairs(PlayerData.inventory) do
        if s.name == name then n = n + s.count end
    end
    return n
end

local function clientSearch(search, items, metadata)
    while not PlayerData.loaded do Wait(50) end
    if search == 'slots' then search = 1 elseif search == 'count' then search = 2 end

    local single = type(items) == 'string' or (type(items) == 'table' and #items == 1)
    local list = type(items) == 'string' and { items } or items
    if type(list) ~= 'table' then return false end
    local result, anyFound = {}, false
    for _, raw in ipairs(list) do
        local name = NormalizeItem(raw)
        local sl, c = {}, 0
        for slotId, s in pairs(PlayerData.inventory) do
            if s.name == name then sl[#sl + 1] = s; c = c + s.count end
        end
        if c > 0 then anyFound = true end
        result[name] = search == 1 and sl or c
    end
    if single then
        local v = result[NormalizeItem(type(items) == 'string' and items or items[1])]
        if search == 1 then if not v or #v == 0 then return false end return v
        else return v or 0 end
    end
    if not anyFound then return false end
    return result
end
exports('Search', clientSearch)
exports('GetItemCount', function(itemName, metadata, strict) return localCount(itemName, metadata, strict) end)
exports('GetPlayerItems', function() return PlayerData.inventory end)
exports('GetPlayerWeight', function() return PlayerData.weight end)
exports('GetPlayerMaxWeight', function() return PlayerData.maxWeight end)
exports('GetSlotWithItem', function(itemName, metadata, strict)
    local name = NormalizeItem(itemName)
    for slotId, s in pairs(PlayerData.inventory) do if s.name == name then return s end end
    return nil
end)
exports('GetSlotsWithItem', function(itemName, metadata, strict)
    local name = NormalizeItem(itemName); local out = {}
    for _, s in pairs(PlayerData.inventory) do if s.name == name then out[#out + 1] = s end end
    return out
end)
exports('GetSlotIdWithItem', function(itemName, metadata, strict)
    local name = NormalizeItem(itemName)
    for slotId, s in pairs(PlayerData.inventory) do if s.name == name then return slotId end end
    return nil
end)
exports('getCurrentWeapon', function() return currentWeapon end)

exports('notify', function(data)
    if data and data.text and not data.description then data.description = data.text end
    lib.notify(data)
end)
RegisterNetEvent('ox_inventory:notify', function(data) exports[CurrentResource]:notify(data) end)

RegisterNetEvent('ox_inventory:itemNotify', function(data)
    if not data then return end
    local first = data[1]
    local def = (type(first) == 'table' and first) or GetItemData(first) or { name = first, label = first }
    nui('itemNotify', { def, data[2], data[3] })
end)
exports('displayMetadata', function() end)
exports('setStashTarget', function(id, owner) stashTarget = id end)
exports('suppressItemNotifications', function() end)
RegisterNetEvent('ox_inventory:suppressItemNotifications', function() end)
exports('weaponWheel', function(state) end)
exports('Progress', function(options, completed)
    local ok = lib.progressBar(options)
    if completed then completed(not ok) end
end)
exports('ProgressActive', function() return lib.progressActive() end)
exports('CancelProgress', function() return lib.cancelProgress() end)
exports('Keyboard', function(...) return lib.inputDialog(...) end)

RegisterNetEvent('qbx_core:client:onGroupUpdate', function(groupName, grade)
    PlayerData.groups = PlayerData.groups or {}
    PlayerData.groups[groupName] = grade
end)

CreateThread(function()
    while true do
        Wait(500)
        if invOpen and (IsEntityDead(ped()) or LocalPlayer.state.invBusy) then closeInventory() end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == CurrentResource then SetNuiFocus(false, false) end
end)


local dropProps = {}

spawnDrop = function(dropId, info)
    if not Config.dropProps or dropProps[dropId] then return end
    info = info or {}
    local coords = info.coords
    if not coords then return end
    local model = info.model or Config.dropModel
    local hash = type(model) == 'number' and model or joaat(model)
    RequestModel(hash)
    local tries = 0
    while not HasModelLoaded(hash) and tries < 100 do Wait(10); tries = tries + 1 end
    if not HasModelLoaded(hash) then return end
    local obj = CreateObject(hash, coords.x + 0.0, coords.y + 0.0, coords.z - 0.95, false, false, false)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    dropProps[dropId] = obj
    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:addLocalEntity(obj, {
            { name = 'w2f_drop_' .. dropId, icon = 'fas fa-box-open', label = 'Pick up',
              distance = 2.0, onSelect = function() openInventory('drop', { id = dropId }) end }
        })
    end
end

removeDropProp = function(dropId)
    local obj = dropProps[dropId]
    if not obj then return end
    if DoesEntityExist(obj) then
        if GetResourceState('ox_target') == 'started' then exports.ox_target:removeLocalEntity(obj) end
        DeleteEntity(obj)
    end
    dropProps[dropId] = nil
end

RegisterNetEvent('ox_inventory:createDrop', function(dropId, info, _, model)
    info = info or {}
    info.model = info.model or model
    spawnDrop(dropId, info)
end)
RegisterNetEvent('ox_inventory:removeDrop', function(dropId) removeDropProp(dropId) end)

throwItemFn = function(slotId, count)
    local item = PlayerData.inventory[slotId]; if not item then return end
    local land = GetOffsetFromEntityInWorldCoords(ped(), 0.0, 5.0, -0.6)
    lib.callback.await('wf_inventory:throwItem', false, {
        slot = slotId, count = count or 1, coords = { x = land.x, y = land.y, z = land.z } })
end

exports('openCraftingBench', function(id) openInventory('crafting', { id = id }) end)
exports('openShop', function(data) openInventory('shop', data) end)
RegisterCommand('craft', function(_, args) openInventory('crafting', { id = args[1] or 'workbench' }) end, false)
RegisterCommand('items', function() openInventory('admin', {}) end, false)

RegisterCommand('+w2fthrow', function()
    if currentWeapon and currentWeapon.slot then throwItemFn(currentWeapon.slot, 1) end
end, false)
RegisterCommand('-w2fthrow', function() end, false)
RegisterKeyMapping('+w2fthrow', 'Throw equipped item', 'keyboard', 'G')

WClient = { openInventory = openInventory }
