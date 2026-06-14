--[[ w2f-inventory admin command suite.
     A full set of inventory management commands, all admin-gated through the
     same isAdmin check used by /adminitems (ACE group.admin / w2finv.admin /
     command.* or qbx_core:HasGroup). Works from the server console too. ]]

local function isAdmin(src)
    if src == 0 then return true end                 -- server console / rcon
    if WAdmin and WAdmin.isAdmin then return WAdmin.isAdmin(src) end
    return IsPlayerAceAllowed(src, 'group.admin') or IsPlayerAceAllowed(src, 'w2finv.admin')
end

-- notify the command issuer (player toast or console print)
local function reply(src, msg, kind)
    kind = kind or 'inform'
    if src == 0 then
        print(('^3[w2f-inventory]^7 %s'):format(msg))
    else
        TriggerClientEvent('ox_inventory:notify', src, { type = kind, description = msg })
    end
end

-- a longer, multi-line listing (chat for players, print for console)
local function listReply(src, lines)
    if src == 0 then
        for i = 1, #lines do print('  ' .. lines[i]) end
    else
        for i = 1, #lines do
            TriggerClientEvent('chat:addMessage', src, { args = { '[inventory]', lines[i] } })
        end
    end
end

local function playerName(id)
    local ok, p = pcall(function() return exports.qbx_core:GetPlayer(id) end)
    if ok and p and p.PlayerData then
        local ci = p.PlayerData.charinfo
        if ci then return ('%s %s'):format(ci.firstname or '', ci.lastname or '') end
    end
    return GetPlayerName(id) or ('player ' .. tostring(id))
end

-- resolve a player target into a loaded inventory; returns id, inv or nil + error
local function resolveTarget(id)
    id = tonumber(id)
    if not id then return nil, nil, 'No player id given.' end
    local inv = WInv and WInv.getInv(id)
    if not inv or inv.type ~= 'player' then return nil, nil, ('Player %d has no loaded inventory.'):format(id) end
    return id, inv
end

-- validate an item name against the catalog (rejects typos)
local function resolveItem(name)
    local key = NormalizeItem(name)
    if not key or not ItemData[key] then return nil end
    return key
end

local function gate(src)
    if isAdmin(src) then return true end
    reply(src, 'You do not have permission to use this command.', 'error')
    return false
end

--==================================================================--
--  /giveitem [id] [item] [count]   — give an item to a player
--==================================================================--
lib.addCommand('giveitem', {
    help = 'Give an item to a player',
    params = {
        { name = 'target', type = 'playerId', help = 'Target player id' },
        { name = 'item',   type = 'string',   help = 'Item name' },
        { name = 'count',  type = 'number',   help = 'Amount (default 1)', optional = true },
    },
}, function(source, args)
    if not gate(source) then return end
    local id, _, err = resolveTarget(args.target)
    if not id then return reply(source, err, 'error') end
    local item = resolveItem(args.item)
    if not item then return reply(source, ('Unknown item "%s".'):format(args.item), 'error') end
    local count = math.max(1, math.floor(args.count or 1))

    local ok = WInv.addItem(id, item, count)
    if ok then
        reply(source, ('Gave %dx %s to %s.'):format(count, item, playerName(id)), 'success')
        if id ~= source then reply(id, ('You received %dx %s.'):format(count, item), 'success') end
    else
        reply(source, ('Could not give item (inventory full?).'), 'error')
    end
end)

--==================================================================--
--  /removeitem [id] [item] [count]  — remove an item from a player
--==================================================================--
lib.addCommand('removeitem', {
    help = 'Remove an item from a player',
    params = {
        { name = 'target', type = 'playerId', help = 'Target player id' },
        { name = 'item',   type = 'string',   help = 'Item name' },
        { name = 'count',  type = 'number',   help = 'Amount (default 1)', optional = true },
    },
}, function(source, args)
    if not gate(source) then return end
    local id, _, err = resolveTarget(args.target)
    if not id then return reply(source, err, 'error') end
    local item = resolveItem(args.item)
    if not item then return reply(source, ('Unknown item "%s".'):format(args.item), 'error') end
    local count = math.max(1, math.floor(args.count or 1))

    local ok = WInv.removeItem(id, item, count)
    if ok then
        reply(source, ('Removed %dx %s from %s.'):format(count, item, playerName(id)), 'success')
    else
        reply(source, ('Could not remove item (not enough owned?).'), 'error')
    end
end)

--==================================================================--
--  /clearinv [id]   — wipe a player's inventory
--==================================================================--
lib.addCommand('clearinv', {
    help = "Clear a player's inventory",
    params = {
        { name = 'target', type = 'playerId', help = 'Target player id' },
    },
}, function(source, args)
    if not gate(source) then return end
    local id, _, err = resolveTarget(args.target)
    if not id then return reply(source, err, 'error') end
    exports[CurrentResource]:ClearInventory(id)
    reply(source, ('Cleared inventory of %s.'):format(playerName(id)), 'success')
    if id ~= source then reply(id, 'Your inventory was cleared by an admin.', 'inform') end
end)

--==================================================================--
--  /viewinv [id]   — open a live view of a player's inventory
--==================================================================--
lib.addCommand('viewinv', {
    help = "Inspect a player's inventory",
    params = {
        { name = 'target', type = 'playerId', help = 'Target player id' },
    },
}, function(source, args)
    if not gate(source) then return end
    if source == 0 then return reply(source, 'This command must be run in-game.', 'error') end
    local id, _, err = resolveTarget(args.target)
    if not id then return reply(source, err, 'error') end
    exports[CurrentResource]:InspectInventory(source, id)
end)

--==================================================================--
--  /itemcount [id] [item]   — how many of an item a player has
--==================================================================--
lib.addCommand('itemcount', {
    help = "Count how many of an item a player has",
    params = {
        { name = 'target', type = 'playerId', help = 'Target player id' },
        { name = 'item',   type = 'string',   help = 'Item name' },
    },
}, function(source, args)
    if not gate(source) then return end
    local id, _, err = resolveTarget(args.target)
    if not id then return reply(source, err, 'error') end
    local item = resolveItem(args.item)
    if not item then return reply(source, ('Unknown item "%s".'):format(args.item), 'error') end
    local n = WInv.getItemCount(id, item)
    reply(source, ('%s has %dx %s.'):format(playerName(id), n, item), 'inform')
end)

--==================================================================--
--  /checkinv [id]   — list everything a player is carrying
--==================================================================--
lib.addCommand('checkinv', {
    help = "List everything a player is carrying",
    params = {
        { name = 'target', type = 'playerId', help = 'Target player id' },
    },
}, function(source, args)
    if not gate(source) then return end
    local id, inv, err = resolveTarget(args.target)
    if not id then return reply(source, err, 'error') end
    local lines, total = {}, 0
    for _, slot in pairs(inv.items) do
        lines[#lines + 1] = ('%dx %s (slot %d)'):format(slot.count, slot.name, slot.slot)
        total = total + 1
    end
    table.sort(lines)
    reply(source, ('%s — %d stacks, %.1f/%.1f kg'):format(playerName(id), total, (inv.weight or 0) / 1000, (inv.maxWeight or 0) / 1000), 'inform')
    if total == 0 then return reply(source, 'Inventory is empty.', 'inform') end
    listReply(source, lines)
end)

--==================================================================--
--  /confiscate [id]  /  /returninv [id]
--==================================================================--
lib.addCommand('confiscate', {
    help = "Confiscate and store a player's inventory",
    params = {
        { name = 'target', type = 'playerId', help = 'Target player id' },
    },
}, function(source, args)
    if not gate(source) then return end
    local id, _, err = resolveTarget(args.target)
    if not id then return reply(source, err, 'error') end
    exports[CurrentResource]:ConfiscateInventory(id)
    reply(source, ('Confiscated inventory of %s.'):format(playerName(id)), 'success')
end)

lib.addCommand('returninv', {
    help = "Return a confiscated inventory to a player",
    params = {
        { name = 'target', type = 'playerId', help = 'Target player id' },
    },
}, function(source, args)
    if not gate(source) then return end
    local id, _, err = resolveTarget(args.target)
    if not id then return reply(source, err, 'error') end
    exports[CurrentResource]:ReturnInventory(id)
    reply(source, ('Returned confiscated inventory to %s.'):format(playerName(id)), 'success')
end)

--==================================================================--
--  /listitems [filter]   — search the item catalog
--==================================================================--
lib.addCommand('listitems', {
    help = 'Search the item catalog by name',
    params = {
        { name = 'filter', type = 'string', help = 'Text to search for', optional = true },
    },
}, function(source, args)
    if not gate(source) then return end
    local filter = args.filter and args.filter:lower() or nil
    local matches = {}
    for name, def in pairs(ItemData) do
        if type(name) == 'string' and (not filter or name:find(filter, 1, true) or (def.label and def.label:lower():find(filter, 1, true))) then
            matches[#matches + 1] = ('%s — %s'):format(name, def.label or name)
        end
    end
    table.sort(matches)
    reply(source, ('%d item(s) matched%s.'):format(#matches, filter and (' "' .. filter .. '"') or ''), 'inform')
    local cap = 40
    local shown = {}
    for i = 1, math.min(cap, #matches) do shown[i] = matches[i] end
    if #matches > cap then shown[#shown + 1] = ('...and %d more (refine your search).'):format(#matches - cap) end
    listReply(source, shown)
end)

print('^2[w2f-inventory] admin command suite loaded^7')
