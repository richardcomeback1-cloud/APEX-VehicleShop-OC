VehicleShopModules = VehicleShopModules or {}
VehicleShopModules.Economy = VehicleShopModules.Economy or {}

function VehicleShopModules.Economy.canAfford(xPlayer, payment, amount)
    if payment == 'cash' or payment == 'money' then
        return xPlayer.getAccount('money').money >= amount
    elseif payment == 'bank' then
        return xPlayer.getAccount('bank').money >= amount
    end
    return false
end

function VehicleShopModules.Economy.removeMoney(xPlayer, payment, amount)
    if payment == 'cash' or payment == 'money' then
        xPlayer.removeAccountMoney('money', amount)
    elseif payment == 'bank' then
        xPlayer.removeAccountMoney('bank', amount)
    end
end
