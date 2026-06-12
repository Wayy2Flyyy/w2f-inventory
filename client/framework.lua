--[[ Framework bridge (client).
     Normalizes Qbox (qbx_core), QBCore (qb-core) and ESX (es_extended) for the
     handful of things the client needs: current money, money-change refresh and
     job/gang (group) updates. ]]

local ftype = Config.framework

local QB, ESX

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

-- Returns { money = { cash = n, bank = n } } or nil.
function Framework.GetMoney()
    if not ensureCore() then return nil end
    if ftype == 'qbx' then
        local ok, pd = pcall(function() return exports.qbx_core:GetPlayerData() end)
        if ok and pd and pd.money then return { cash = pd.money.cash or 0, bank = pd.money.bank or 0 } end
    elseif ftype == 'qb' then
        local pd = QB.Functions.GetPlayerData()
        if pd and pd.money then return { cash = pd.money.cash or 0, bank = pd.money.bank or 0 } end
    elseif ftype == 'esx' then
        local pd = ESX.GetPlayerData()
        local cash, bank = 0, 0
        for _, acc in ipairs((pd and pd.accounts) or {}) do
            if acc.name == 'money' then cash = acc.money or 0
            elseif acc.name == 'bank' then bank = acc.money or 0 end
        end
        return { cash = cash, bank = bank }
    end
    return nil
end

-- Fires `fn()` whenever the player's money changes.
function Framework.RegisterMoneyChange(fn)
    if ftype == 'qbx' or ftype == 'qb' then
        RegisterNetEvent('QBCore:Client:OnMoneyChange', function() fn() end)
    elseif ftype == 'esx' then
        RegisterNetEvent('esx:setAccountMoney', function() fn() end)
        RegisterNetEvent('esx:setMoney', function() fn() end)
    end
end

-- Fires `fn(groupName, grade)` on job/gang change.
function Framework.RegisterGroupUpdate(fn)
    if ftype == 'qbx' then
        RegisterNetEvent('qbx_core:client:onGroupUpdate', function(groupName, grade) fn(groupName, grade) end)
    elseif ftype == 'qb' then
        RegisterNetEvent('QBCore:Client:OnJobUpdate', function(job) if job then fn(job.name, job.grade and job.grade.level or 0) end end)
        RegisterNetEvent('QBCore:Client:OnGangUpdate', function(gang) if gang then fn(gang.name, gang.grade and gang.grade.level or 0) end end)
    elseif ftype == 'esx' then
        RegisterNetEvent('esx:setJob', function(job) if job then fn(job.name, job.grade or 0) end end)
    end
end
