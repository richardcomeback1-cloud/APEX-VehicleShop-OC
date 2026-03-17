VehicleShopModules = VehicleShopModules or {}
VehicleShopModules.UI = VehicleShopModules.UI or {}

function VehicleShopModules.UI.buildPurchaseEmbed(data)
    return {
        {
            ["color"] = 0x2ECC71,
            ["description"] =
                "**INFORMATION - ข้อมูล**\n" ..
                "Name : `" .. tostring(data.playerName or 'N/A') .. "`\n" ..
                "Discord Name : `" .. tostring(data.discordName or 'N/A') .. "`\n" ..
                "Discord Identifier : `" .. tostring(data.discordIdentifier or 'N/A') .. "`\n" ..
                "SteamID : `" .. tostring(data.steamId or 'N/A') .. "`\n\n" ..
                "**VEHICLE - ข้อมูลรถ**\n" ..
                "Car : `" .. tostring(data.carName or 'N/A') .. "`\n" ..
                "Model : `" .. tostring(data.model or 'N/A') .. "`\n" ..
                "Nameplate : `" .. tostring(data.plate or 'N/A') .. "`\n" ..
                "Price : `" .. tostring(data.price or '0') .. "`",
            ["footer"] = {
                ["text"] = "Time • " .. os.date("%d/%m/%Y %I:%M %p")
            }
        }
    }
end
