local function loadData(name)
    local path = ('data/%s.lua'):format(name)
    local content = LoadResourceFile(CurrentResource, path)
    if not content then
        if IsServer then print(('^3[w2f-inventory] missing data file %s^7'):format(path)) end
        return {}
    end
    local chunk, err = load(content, ('@@%s/%s'):format(CurrentResource, path))
    if not chunk then
        print(('^1[w2f-inventory] error loading %s: %s^7'):format(path, err))
        return {}
    end
    local ok, result = pcall(chunk)
    if not ok then
        print(('^1[w2f-inventory] error running %s: %s^7'):format(path, result))
        return {}
    end
    return type(result) == 'table' and result or {}
end

function NormalizeItem(name)
    if type(name) ~= 'string' then return nil end
    local lower = name:lower()
    if lower:find('^weapon_') or lower:find('^ammo_') then
        return name:upper()
    end
    return lower
end

local function isWeaponName(name)
    return type(name) == 'string' and name:upper():find('^WEAPON_') ~= nil
end

local function isAmmoName(name)
    return type(name) == 'string' and name:lower():find('^ammo[-_]') ~= nil
end

local function prettify(name)
    local s = tostring(name):gsub('[_%-]', ' ')
    return (s:gsub('(%a)([%w]*)', function(a, b) return a:upper() .. b end))
end

ItemData = {}

local function register(rawName, def)
    if type(def) ~= 'table' then return end
    local name = NormalizeItem(rawName)
    if not name then return end
    def.name   = name
    def.label  = def.label or prettify(name)
    def.weight = tonumber(def.weight) or 0
    if def.stack == nil then def.stack = not isWeaponName(name) end
    if def.close == nil then def.close = true end
    def.client = def.client or {}

    if not def.client.image then def.client.image = name .. '.png' end
    def.weapon = isWeaponName(name) or def.weapon or nil
    def.ammo   = isAmmoName(name) or def.ammoType or nil
    ItemData[name] = def
end

do
    local imageItems = loadData('image_items')
    local items      = loadData('items')
    local weapons    = loadData('weapons')
    for k, v in pairs(imageItems) do register(k, v) end
    for k, v in pairs(items)      do register(k, v) end
    for k, v in pairs(weapons)    do register(k, v) end
end

local generatedCache = {}

function GetItemData(name)
    local key = NormalizeItem(name)
    if not key then return nil end
    local def = ItemData[key]
    if def then return def end

    local gen = generatedCache[key]
    if not gen then
        gen = {
            name = key,
            label = prettify(key),
            weight = 0,
            stack = not isWeaponName(key),
            close = true,
            client = { image = key .. '.png' },
            weapon = isWeaponName(key) or nil,
            ammo = isAmmoName(key) or nil,
            generated = true,
        }
        generatedCache[key] = gen
    end
    return gen
end

function IsWeapon(name)  return isWeaponName(name) end
function IsAmmo(name)    return isAmmoName(name) end

local function ItemsExport(name)
    if name == nil then return ItemData end
    return GetItemData(name)
end

exports('Items', ItemsExport)
exports('ItemList', ItemsExport)

function BuildItemCatalog()
    local catalog = {}
    for name, def in pairs(ItemData) do
        local buttons
        if def.buttons then
            buttons = {}
            for i = 1, #def.buttons do
                buttons[i] = { label = def.buttons[i].label, group = def.buttons[i].group }
            end
        end
        catalog[name] = {
            label = def.label,
            stack = def.stack,
            close = def.close,
            description = def.description,
            buttons = buttons,
            ammoName = def.ammoname,
            image = def.client and def.client.image or (name .. '.png'),
        }
    end
    return catalog
end
