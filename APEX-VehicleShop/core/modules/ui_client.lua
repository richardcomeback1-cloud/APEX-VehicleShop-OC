VehicleShopClientModules = VehicleShopClientModules or {}
VehicleShopClientModules.UI = VehicleShopClientModules.UI or {}

function VehicleShopClientModules.UI.notifyByProvider(configNotify, esx, msg, level)
    level = level or 'info'
    local provider = (configNotify and configNotify.Provider) or 'ssr'

    if provider == 'esx' and esx and esx.ShowNotification then
        esx.ShowNotification(msg)
        return true
    end

    return false
end
