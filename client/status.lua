local INJURY_PREFIX = 'qbx_medical:injuries:'
local BLEED_BAG     = 'qbx_medical:bleedLevel'
local LIMB_MAP = {
    head  = { 'HEAD', 'NECK' },
    torso = { 'SPINE', 'UPPER_BODY', 'LOWER_BODY' },
    l_arm = { 'LARM', 'LHAND', 'LFINGER' },
    r_arm = { 'RARM', 'RHAND', 'RFINGER' },
    l_leg = { 'LLEG', 'LFOOT' },
    r_leg = { 'RLEG', 'RFOOT' },
}

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi else return v end
end

local SEVERITY_HEALTH = { [1] = 75, [2] = 45, [3] = 22, [4] = 10 }

local function limbHealth(parts)
    local worst = 0
    for i = 1, #parts do
        local injury = LocalPlayer.state[INJURY_PREFIX .. parts[i]]
        local severity = injury and injury.severity
        if severity and severity > worst then worst = severity end
    end
    if worst == 0 then return 100 end
    return SEVERITY_HEALTH[worst] or clamp(100 - worst * 25, 5, 100)
end

local function medicalReady()
    return GetResourceState('qbx_medical') == 'started'
end

local function buildStatus()
    local ped = PlayerPedId()
    local playerId = PlayerId()
    local raw = GetEntityHealth(ped)
    local health = raw <= 0 and 0 or clamp(raw - 100, 0, 100)
    local hasMedical = medicalReady()

    local limbs
    if hasMedical then
        limbs = {
            head  = limbHealth(LIMB_MAP.head),
            torso = limbHealth(LIMB_MAP.torso),
            l_arm = limbHealth(LIMB_MAP.l_arm),
            r_arm = limbHealth(LIMB_MAP.r_arm),
            l_leg = limbHealth(LIMB_MAP.l_leg),
            r_leg = limbHealth(LIMB_MAP.r_leg),
        }
    else

        limbs = { head = health, torso = health, l_arm = health, r_arm = health, l_leg = health, r_leg = health }
    end

    return {
        health  = health,
        armor   = clamp(GetPedArmour(ped), 0, 100),
        hunger  = clamp(LocalPlayer.state.hunger or 100, 0, 100),
        thirst  = clamp(LocalPlayer.state.thirst or 100, 0, 100),
        stamina = clamp(100 - GetPlayerSprintStaminaRemaining(playerId), 0, 100),
        bleed   = hasMedical and (LocalPlayer.state[BLEED_BAG] or 0) or 0,
        limbs   = limbs,
    }
end

CreateThread(function()
    while true do
        if LocalPlayer.state.invOpen then
            SendNUIMessage({ action = 'status', data = buildStatus() })
            Wait(250)
        else
            Wait(500)
        end
    end
end)
