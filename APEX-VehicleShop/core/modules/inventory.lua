VehicleShopModules = VehicleShopModules or {}
VehicleShopModules.Inventory = VehicleShopModules.Inventory or {}

function VehicleShopModules.Inventory.countItem(xPlayer, itemName)
    if not xPlayer or not xPlayer.getInventoryItem then
        return 0
    end

    local item = xPlayer.getInventoryItem(itemName)
    if item and item.count then
        return tonumber(item.count) or 0
    end

    return 0
end
