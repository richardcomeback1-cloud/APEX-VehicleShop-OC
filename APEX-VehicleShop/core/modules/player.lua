VehicleShopModules = VehicleShopModules or {}

VehicleShopModules.Player = VehicleShopModules.Player or {}

local cache = {}

function VehicleShopModules.Player.getCached(esx, src, ttlMs)
    local now = GetGameTimer()
    local cached = cache[src]
    if cached and cached.expiresAt > now and cached.value then
        return cached.value
    end

    local xPlayer = esx.GetPlayerFromId(src)
    cache[src] = {
        value = xPlayer,
        expiresAt = now + (tonumber(ttlMs) or 1000)
    }

    return xPlayer
end

function VehicleShopModules.Player.invalidate(src)
    cache[src] = nil
end

function VehicleShopModules.Player.prune()
    local now = GetGameTimer()
    for src, entry in pairs(cache) do
        if (not entry) or now > (tonumber(entry.expiresAt) or 0) then
            cache[src] = nil
        end
    end
end

function VehicleShopModules.Player.getSteamIdentifier(xPlayer)
    local ids = xPlayer.getIdentifiers and xPlayer.getIdentifiers() or GetPlayerIdentifiers(xPlayer.source)
    if ids then
        for _, id in pairs(ids) do
            if type(id) == 'string' and id:sub(1, 6) == 'steam:' then
                return id
            end
        end
    end
    return 'N/A'
end

function VehicleShopModules.Player.getDiscordIdentifier(xPlayer)
    local ids = xPlayer.getIdentifiers and xPlayer.getIdentifiers() or GetPlayerIdentifiers(xPlayer.source)
    if ids then
        for _, id in pairs(ids) do
            if type(id) == 'string' and id:sub(1, 8) == 'discord:' then
                return id
            end
        end
    end
    return 'N/A'
end

function VehicleShopModules.Player.getDiscordUserId(discordIdentifier)
    local raw = tostring(discordIdentifier or '')
    local discordId = raw:match('^discord:(%d+)$')
    return discordId or 'N/A'
end
