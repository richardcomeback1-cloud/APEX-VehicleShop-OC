VehicleShopModules = VehicleShopModules or {}
VehicleShopModules.Jobs = VehicleShopModules.Jobs or {}

local restrictedJobs = {
    ambulance = true,
    police = true,
    council = true
}

function VehicleShopModules.Jobs.isRestricted(category)
    return restrictedJobs[tostring(category)] == true
end

function VehicleShopModules.Jobs.canAccessVehicle(xPlayer, cfg)
    if not cfg then
        return false
    end

    local category = tostring(cfg.category or '')
    if not VehicleShopModules.Jobs.isRestricted(category) then
        return true
    end

    if not xPlayer or not xPlayer.job then
        return false
    end

    if xPlayer.job.name ~= category then
        return false
    end

    local grade = tonumber(cfg.grade or 0) or 0
    return (xPlayer.job.grade or 0) >= grade
end
