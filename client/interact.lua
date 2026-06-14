local function loadData(path)
    local content = LoadResourceFile(CurrentResource, path)
    if not content then return {} end
    local fn = load(content, ('@@%s/%s'):format(CurrentResource, path))
    if not fn then return {} end
    local ok, res = pcall(fn)
    return ok and type(res) == 'table' and res or {}
end

local hasTarget = GetResourceState('ox_target') == 'started'

local function addBlip(coords, blip, label)
    local b = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(b, blip.sprite or 52)
    SetBlipColour(b, blip.color or 0)
    SetBlipScale(b, blip.scale or 0.7)
    SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(b)
end

local zoneId = 0
local function addPoint(coords, icon, label, onUse)
    if hasTarget then
        zoneId = zoneId + 1
        exports.ox_target:addSphereZone({
            coords = coords, radius = 1.6,
            options = {
                { name = ('w2finv_zone_%d'):format(zoneId), icon = icon, label = label, distance = 2.2, onSelect = onUse },
            },
        })
    else
        local point = lib.points.new({ coords = coords, distance = 2.0 })
        function point:onEnter() lib.showTextUI(('[E] %s'):format(label)) end
        function point:onExit() lib.hideTextUI() end
        function point:nearby()
            if IsControlJustReleased(0, 38) then onUse() end
        end
    end
end

CreateThread(function()
    while not WClient do Wait(100) end

    local shops = loadData('data/shops.lua')
    for shopType, shop in pairs(shops) do
        local label = shop.label or shopType
        for i = 1, #(shop.locations or {}) do
            local c = shop.locations[i]
            if shop.blip then addBlip(c, shop.blip, label) end
            addPoint(c, 'fas fa-cart-shopping', ('Open %s'):format(label), function()
                WClient.openInventory('shop', { type = shopType })
            end)
        end
    end

    local benches = loadData('data/crafting.lua')
    for benchId, bench in pairs(benches) do
        local label = bench.label or benchId
        for i = 1, #(bench.locations or {}) do
            local c = bench.locations[i]
            if bench.blip then addBlip(c, bench.blip, label) end
            addPoint(c, 'fas fa-screwdriver-wrench', ('Use %s'):format(label), function()
                WClient.openInventory('crafting', { id = benchId })
            end)
        end
    end
end)
