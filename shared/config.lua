local function jsonConvar(name, default)
    local raw = GetConvar(name, default)
    local ok, decoded = pcall(json.decode, raw)
    if ok and decoded ~= nil then return decoded end
    return json.decode(default)
end

Config = {

    framework   = GetConvar('inventory:framework', 'qbx'),

    playerSlots = GetConvarInt('inventory:slots', 50),
    playerWeight= GetConvarInt('inventory:weight', 85000),

    dropSlots   = GetConvarInt('inventory:dropslots', 50),
    dropWeight  = GetConvarInt('inventory:dropweight', 100000),

    accounts    = jsonConvar('inventory:accounts', '["money"]'),

    police      = jsonConvar('inventory:police', '["police","bcso","sasp"]'),

    imagePath   = GetConvar('inventory:imagepath', 'nui://w2f-inventory/images'),

    clearStashes= GetConvar('inventory:clearstashes', '6 MONTH'),
    trimPlate   = GetConvarInt('inventory:trimplate', 1) == 1,
    logLevel    = GetConvarInt('inventory:loglevel', 1),

    screenBlur  = GetConvarInt('inventory:screenblur', 1) == 1,
    keys        = jsonConvar('inventory:keys', '["TAB","K","F1"]'),
    giveList    = GetConvarInt('inventory:giveplayerlist', 1) == 1,
    itemNotify  = GetConvarInt('inventory:itemnotify', 1) == 1,

    dropProps   = GetConvarInt('inventory:dropprops', 1) == 1,
    dropModel   = GetConvar('inventory:dropmodel', 'prop_med_bag_01b'),
}

AccountMoneyType = {
    money       = 'cash',
    cash        = 'cash',
    bank        = 'bank',
    black_money = 'black_money',
    crypto      = 'crypto',
}

IsAccountItem = {}
for i = 1, #Config.accounts do
    IsAccountItem[Config.accounts[i]] = true
end

IsAccountItem.money = true

IsPoliceJob = {}
for i = 1, #Config.police do
    IsPoliceJob[Config.police[i]] = true
end

CurrentResource = GetCurrentResourceName()
IsServer = IsDuplicityVersion()
