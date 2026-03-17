VehicleShopClientModules = VehicleShopClientModules or {}
VehicleShopClientModules.Jobs = VehicleShopClientModules.Jobs or {}

function VehicleShopClientModules.Jobs.matches(jobName, expected)
    if expected == nil then
        return true
    end

    if type(expected) == 'table' then
        for i = 1, #expected do
            if tostring(expected[i]) == tostring(jobName) then
                return true
            end
        end
        return false
    end

    return tostring(jobName) == tostring(expected)
end
