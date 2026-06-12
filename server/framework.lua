--[[ Framework bridge (server).
     Normalizes Qbox (qbx_core), QBCore (qb-core) and ESX (es_extended) behind a
     single QB-shaped facade so the rest of the resource never has to branch on
     framework. Every player object returned by Framework.GetPlayer exposes the
     same surface the resource already relied on:

         player.PlayerData.source / citizenid / identifier
         player.PlayerData.money[cash|bank|black_money|crypto]
         player.PlayerData.charinfo.firstname / lastname
         player.PlayerData.job   = { name, label, grade = { level, name } }
         player.PlayerData.gang   = { name,        grade = { level } }
         player.PlayerData.metadata
         player.Functions.SetMoney(type, amount, reason)
         player.Functions.RemoveMoney(type, amount, reason)
         player.Functions.AddMoney(type, amount, reason)
         player.Functions.SetMetaData(key, value)

     For Qbox/QBCore the native object already has this shape, so it is returned
     as-is. For ESX we build a facade around xPlayer. ]]

local ftype = Config.framework

local QBX, QB, ESX

local function ensureCore()
    if ftype == 'qbx' then
        return true
    elseif ftype == 'qb' then
        if not QB then QB = exports['qb-core']:GetCoreObject() end
        return QB ~= nil
    elseif ftype == 'esx' then
        if not ESX then
            local ok, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
            if ok and obj then ESX = obj end
        end
        return ESX ~= nil
    end
    return false
end

Framework = { type = ftype }

-- ESX account name <-> our normalized money key.
local function esxAccount(moneyType)
    if moneyType == 'cash' or moneyType == 'money' then return 'money' end
    return moneyType -- bank, black_money
end

local function esxAccountMoney(xPlayer, account)
    local a = xPlayer.getAccount and xPlayer.getAccount(account)
    return a and a.money or 0
end

local function makeEsxFacade(xPlayer)
    if not xPlayer then return nil end
    local src = xPlayer.source

    local name = (xPlayer.getName and xPlayer.getName()) or xPlayer.name or ''
    local firstname, lastname = name:match('^(%S+)%s+(.*)$')

    local job = xPlayer.job or {}
    local meta = (xPlayer.getMeta and xPlayer.getMeta()) or xPlayer.metadata or {}

    local pd = {
        source     = src,
        citizenid  = xPlayer.identifier,
        identifier = xPlayer.identifier,
        name       = name,
        charinfo   = { firstname = firstname or name or '', lastname = lastname or '' },
        money      = {
            cash        = esxAccountMoney(xPlayer, 'money'),
            bank        = esxAccountMoney(xPlayer, 'bank'),
            black_money = esxAccountMoney(xPlayer, 'black_money'),
        },
        job        = { name = job.name, label = job.label, grade = { level = job.grade or 0, name = job.grade_name } },
        gang       = { name = 'none', grade = { level = 0 } },
        metadata   = meta,
    }
    pd.money.money = pd.money.cash

    local fns = {
        GetMoney    = function(moneyType) return esxAccountMoney(xPlayer, esxAccount(moneyType)) end,
        SetMoney    = function(moneyType, amount) xPlayer.setAccountMoney(esxAccount(moneyType), math.floor(amount + 0.5)) end,
        AddMoney    = function(moneyType, amount) xPlayer.addAccountMoney(esxAccount(moneyType), math.floor(amount + 0.5)) end,
        RemoveMoney = function(moneyType, amount) xPlayer.removeAccountMoney(esxAccount(moneyType), math.floor(amount + 0.5)) end,
        SetMetaData = function(key, value) if xPlayer.setMeta then xPlayer.setMeta(key, value) end end,
    }

    return { PlayerData = pd, Functions = fns, _xPlayer = xPlayer }
end

function Framework.GetPlayer(src)
    if not ensureCore() then return nil end
    if ftype == 'qbx' then
        return exports.qbx_core:GetPlayer(src)
    elseif ftype == 'qb' then
        return QB.Functions.GetPlayer(src)
    elseif ftype == 'esx' then
        return makeEsxFacade(ESX.GetPlayerFromId(src))
    end
    return nil
end

-- Returns a plain array of loaded player source ids.
function Framework.GetPlayers()
    if not ensureCore() then return {} end
    local out = {}
    if ftype == 'qbx' or ftype == 'qb' then
        local map = (ftype == 'qbx' and exports.qbx_core:GetQBPlayers()) or QB.Functions.GetQBPlayers()
        for src in pairs(map or {}) do out[#out + 1] = tonumber(src) or src end
    elseif ftype == 'esx' then
        local list = ESX.GetPlayers() or {}
        for i = 1, #list do out[#out + 1] = tonumber(list[i]) or list[i] end
    end
    return out
end

-- Admin gate used by the item spawner. ACE checks are handled by the caller;
-- this covers the framework's own permission groups.
function Framework.IsAdmin(src)
    if not ensureCore() then return false end
    if ftype == 'qbx' then
        local ok, res = pcall(function() return exports.qbx_core:HasGroup(src, { admin = 0, god = 0 }) end)
        return ok and res ~= false and res ~= nil
    elseif ftype == 'qb' then
        local ok, res = pcall(function() return QB.Functions.HasPermission(src, { 'god', 'admin' }) end)
        return ok and res == true
    elseif ftype == 'esx' then
        local xPlayer = ESX.GetPlayerFromId(src)
        local group = xPlayer and xPlayer.getGroup and xPlayer.getGroup()
        return group == 'admin' or group == 'superadmin'
    end
    return false
end

-- Returns the registered usable-item callback for `name`, or nil.
function Framework.CanUseItem(name)
    if not ensureCore() then return nil end
    if ftype == 'qbx' then
        local ok, cb = pcall(function() return exports.qbx_core:CanUseItem(name) end)
        return ok and cb or nil
    elseif ftype == 'qb' then
        local ok, cb = pcall(function() return QB.Functions.CanUseItem(name) end)
        return ok and cb or nil
    elseif ftype == 'esx' then
        return ESX.UsableItemsCallbacks and ESX.UsableItemsCallbacks[name] or nil
    end
    return nil
end

------------------------------------------------------------------------------
-- Persistence. Player inventories live on the framework's character table:
--   qb / qbx -> players.inventory   keyed by citizenid
--   esx      -> users.inventory     keyed by identifier
------------------------------------------------------------------------------
local dbTable = (ftype == 'esx') and 'users' or 'players'
local dbKey   = (ftype == 'esx') and 'identifier' or 'citizenid'
Framework.dbTable = dbTable
Framework.dbKey   = dbKey

function Framework.EnsureSchema()
    MySQL.query(('ALTER TABLE `%s` ADD COLUMN IF NOT EXISTS `inventory` LONGTEXT'):format(dbTable))
end

function Framework.LoadInventory(id, cb)
    MySQL.scalar(('SELECT `inventory` FROM `%s` WHERE `%s` = ?'):format(dbTable, dbKey), { id }, function(data)
        if not data then return cb({}) end
        local ok, decoded = pcall(json.decode, data)
        cb(ok and type(decoded) == 'table' and decoded or {})
    end)
end

function Framework.SaveInventory(id, encoded)
    MySQL.update(('UPDATE `%s` SET `inventory` = ? WHERE `%s` = ?'):format(dbTable, dbKey), { encoded, id })
end

------------------------------------------------------------------------------
-- Lifecycle event normalization. Handlers are invoked as fn(src, ...).
------------------------------------------------------------------------------
function Framework.RegisterPlayerLoaded(fn)
    if ftype == 'qbx' or ftype == 'qb' then
        RegisterNetEvent('QBCore:Server:PlayerLoaded', function(player)
            local src = type(player) == 'table' and (player.PlayerData and player.PlayerData.source or player.source) or source
            if src then fn(src) end
        end)
    elseif ftype == 'esx' then
        RegisterNetEvent('esx:playerLoaded', function(playerId)
            if playerId then fn(playerId) end
        end)
    end
end

function Framework.RegisterPlayerDropped(fn)
    AddEventHandler('playerDropped', function() fn(source) end)
    if ftype == 'qbx' then
        AddEventHandler('qbx_core:server:playerLoggedOut', function() fn(source) end)
    elseif ftype == 'qb' then
        AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) fn(src or source) end)
    elseif ftype == 'esx' then
        AddEventHandler('esx:playerDropped', function(src) fn(src or source) end)
    end
end

function Framework.RegisterGroupUpdate(fn)
    if ftype == 'qbx' then
        AddEventHandler('qbx_core:server:onGroupUpdate', function(src, groupName, grade) fn(src, groupName, grade) end)
    elseif ftype == 'qb' then
        AddEventHandler('QBCore:Server:OnJobUpdate', function(src, job) if job then fn(src, job.name, job.grade and job.grade.level or 0) end end)
        AddEventHandler('QBCore:Server:OnGangUpdate', function(src, gang) if gang then fn(src, gang.name, gang.grade and gang.grade.level or 0) end end)
    elseif ftype == 'esx' then
        AddEventHandler('esx:setJob', function(src, job) if job then fn(src, job.name, job.grade or 0) end end)
    end
end

print(('^2[w2f-inventory]^7 framework bridge initialized: ^3%s^7'):format(ftype))
