VehicleShopClientModules = VehicleShopClientModules or {}
VehicleShopClientModules.Economy = VehicleShopClientModules.Economy or {}

local function getAccountMoney(esx, accountName)
    local data = esx and esx.GetPlayerData and esx.GetPlayerData() or nil
    local accounts = data and data.accounts or {}

    for i = 1, #accounts do
        local account = accounts[i]
        if account and account.name == accountName then
            return tonumber(account.money) or 0
        end
    end

    return 0
end

function VehicleShopClientModules.Economy.getCash(esx)
    return getAccountMoney(esx, 'money')
end

function VehicleShopClientModules.Economy.getBank(esx)
    return getAccountMoney(esx, 'bank')
end
