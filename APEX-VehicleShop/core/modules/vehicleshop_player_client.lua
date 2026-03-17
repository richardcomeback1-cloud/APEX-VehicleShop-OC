VehicleShopClientModules = VehicleShopClientModules or {}
VehicleShopClientModules.Player = VehicleShopClientModules.Player or {}

function VehicleShopClientModules.Player.getData(esx)
    if not esx or not esx.GetPlayerData then
        return {}
    end

    return esx.GetPlayerData() or {}
end

function VehicleShopClientModules.Player.getJob(esx)
    local data = VehicleShopClientModules.Player.getData(esx)
    return data.job or {}
end
