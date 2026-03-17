VehicleShopClientModules = VehicleShopClientModules or {}
VehicleShopClientModules.Inventory = VehicleShopClientModules.Inventory or {}

function VehicleShopClientModules.Inventory.countItem(esx, itemName)
    local data = esx and esx.GetPlayerData and esx.GetPlayerData() or nil
    local inventory = data and data.inventory or {}

    for i = 1, #inventory do
        local item = inventory[i]
        if item and item.name == itemName then
            return tonumber(item.count) or 0
        end
    end

    return 0
end
