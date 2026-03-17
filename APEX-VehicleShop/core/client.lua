ESX = nil

Val = GetCurrentResourceName()
ValDev = {
    indexshop = nil,
    IsInShopMenu = false,
    Categories = {},
    Vehicles = {},
    LastVehicles = {},
    openfocus = false,
    testcarme = false
}

cam = nil
local num = 0

local ClientModules = VehicleShopClientModules or {}
local ClientUi = ClientModules.UI or {}

local playerPedCache = 0
local playerCoordsCache = nil
local nearestZoneState = {
    zone = nil,
    index = nil,
    distSqr = math.huge
}
local nuiState = {
    open = false,
    dataFingerprint = nil
}

local function sqrDistance(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return (dx * dx) + (dy * dy) + (dz * dz)
end

local function getCachedPedAndCoords()
    playerPedCache = PlayerPedId()
    playerCoordsCache = GetEntityCoords(playerPedCache)
    return playerPedCache, playerCoordsCache
end

Citizen.CreateThread(function()
    while ESX == nil do
        TriggerEvent(Config['BaseServer']['clinet_shared_obj'], function(obj) ESX = obj end)
        Citizen.Wait(100)
    end
end)

local function Notify(msg, level)
    level = level or 'info'
    local provider = (ConfigNotify and ConfigNotify.Provider) or 'ssr'

    if provider == 'ssr' then
        local alertType = (ConfigNotify and ConfigNotify.Types and ConfigNotify.Types[level]) or level
        local ok = pcall(function()
            exports[(ConfigNotify and ConfigNotify.SsrResource) or 'ssr_notify']:sendAlert({
                title = 'ร้านรถ',
                msg = msg,
                type = alertType
            })
        end)
        if ok then return end
    elseif provider == 'mythic' then
        local t = (ConfigNotify and ConfigNotify.Types and ConfigNotify.Types[level]) or level
        local ok = pcall(function()
            exports[(ConfigNotify and ConfigNotify.MythicResource) or 'mythic_notify']:DoHudText(t, msg)
        end)
        if ok then return end
    elseif provider == 'esx' and ESX and ESX.ShowNotification then
        if ClientUi.notifyByProvider and ClientUi.notifyByProvider(ConfigNotify, ESX, msg, level) then return end
        ESX.ShowNotification(msg)
        return
    end

    if ClientUi.notifyByProvider then
        ClientUi.notifyByProvider(ConfigNotify, ESX, msg, level)
    end
end

local function notifyError()
    exports[(ConfigNotify and ConfigNotify.SsrResource) or 'ssr_notify']:sendAlert({
        title = 'ร้านรถ',
        msg = 'คุณมีเงินในธนาคารไม่เพียงพอ',
        type = 'error'
    })
end

local function setHudShopState()
    ExecuteCommand('hud')
    ExecuteCommand('closeminimap')
    ExecuteCommand('closehudspeed')
end

local function sendNUIIfChanged(payload)
    local encoded = json.encode(payload)
    if encoded == nuiState.dataFingerprint then
        return
    end

    nuiState.dataFingerprint = encoded
    SendNUIMessage(payload)
end

local function ExitShopUI()
    if not ValDev.IsInShopMenu then return end

    if EnableKeyInShop then EnableKeyInShop() end
    setHudShopState()
    DeleteShopInsideVehicles()

    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, false)
    SetEntityVisible(playerPed, true)

    local config = Config['ZONE_SHOP'][ValDev.indexshop]
    if config and config.ShopEnterShop and config.ShopEnterShop.Pos then
        pcall(function() exports['Val_report']:PlayerBypassTPM() end)
        SetEntityCoords(playerPed, config.ShopEnterShop.Pos.x, config.ShopEnterShop.Pos.y, config.ShopEnterShop.Pos.z)
    end

    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({ closeui = true })

    ValDev.IsInShopMenu = false
    ValDev.openfocus = false
    nuiState.open = false
    nuiState.dataFingerprint = nil

    if cam then
        DestroyCam(cam, false)
        RenderScriptCams(false, false, 0, true, true)
        cam = nil
        num = 0
    end
end

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(xPlayer)
    ESX.PlayerData = xPlayer
end)

RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job)
    ESX.PlayerData.job = job
end)

CreateThread(function()
    for _, v in pairs(Config['Category']) do
        ValDev.Categories[#ValDev.Categories + 1] = { name = v.index, label = v.label }
    end

    for _, veh in pairs(Config['vehicles']) do
        ValDev.Vehicles[#ValDev.Vehicles + 1] = {
            name = veh.name,
            model = veh.model,
            price = veh.price,
            category = veh.category,
            kg = veh.kg,
            grade = veh.grade,
            typecar = veh.typecar,
            class = GetClassNameCar(veh.model)
        }
    end
end)

CreateThread(function()
    local zoneCache = {}
    for k, v in pairs(Config['ZONE_SHOP']) do
        local enterPos = v.ShopEnterShop and v.ShopEnterShop.Pos
        if enterPos then
            zoneCache[#zoneCache + 1] = {
                index = k,
                shop = v.shop,
                enter = v.ShopEnterShop,
                enterPos = vector3(enterPos.x + 0.0, enterPos.y + 0.0, enterPos.z + 0.0)
            }
        end
    end

    while true do
        if ValDev.IsInShopMenu then
            Wait(1000)
        else
            local _, coords = getCachedPedAndCoords()
            local nearestZone, nearestIndex, nearestDistSqr = nil, nil, math.huge

            for i = 1, #zoneCache do
                local zone = zoneCache[i]
                local distSqr = sqrDistance(coords, zone.enterPos)
                if distSqr < nearestDistSqr then
                    nearestDistSqr = distSqr
                    nearestZone = zone
                    nearestIndex = zone.index
                end
            end

            nearestZoneState.zone = nearestZone
            nearestZoneState.index = nearestIndex
            nearestZoneState.distSqr = nearestDistSqr
            if nearestIndex then
                ValDev.indexshop = nearestIndex
            end

            Wait(750)
        end
    end
end)

CreateThread(function()
    while true do
        if ValDev.IsInShopMenu then
            Wait(500)
        else
            local zone = nearestZoneState.zone
            if zone and zone.enter and zone.enter.Type ~= -1 then
                local drawDist = Config.DrawDistance or 20.0
                local drawDistSqr = drawDist * drawDist
                if nearestZoneState.distSqr <= drawDistSqr then
                    local enterPos = zone.enterPos
                    local enter = zone.enter
                    DrawMarker(enter.Type, enterPos.x, enterPos.y, enterPos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, enter.Size.x, enter.Size.y, enter.Size.z, enter.colormarker.r, enter.colormarker.g, enter.colormarker.b, enter.colormarker.a, false, true, 2, false, false, false, false)

                    if nearestZoneState.distSqr <= 4.0 and IsControlJustReleased(0, 38) then
                        OpenShopMenu(zone.shop, nearestZoneState.index)
                    end

                    Wait(0)
                else
                    Wait(250)
                end
            else
                Wait(400)
            end
        end
    end
end)

function OpenShopMenu(shop, indexshop)
    TriggerServerEvent(Val .. ':ExitTest')
    ValDev.IsInShopMenu = true
    setHudShopState()
    DisableKeyInShop()

    local playerPed = PlayerPedId()
    FreezeEntityPosition(playerPed, true)
    SetEntityVisible(playerPed, false)

    local config = Config['ZONE_SHOP'][indexshop]
    pcall(function() exports['Val_report']:PlayerBypassTPM() end)
    SetEntityCoords(playerPed, config.ShopEnterShop.Pos.x, config.ShopEnterShop.Pos.y, config.ShopEnterShop.Pos.z)

    local vehiclesByCategory = {}
    for i = 1, #ValDev.Categories do
        vehiclesByCategory[ValDev.Categories[i].name] = {}
    end

    for i = 1, #ValDev.Vehicles do
        local vehicle = ValDev.Vehicles[i]
        if IsModelInCdimage(GetHashKey(vehicle.model)) then
            local bucket = vehiclesByCategory[vehicle.category]
            if bucket then
                bucket[#bucket + 1] = vehicle
            end
        end
    end

    local category, vehiclebysell = GetCategory(vehiclesByCategory)
    sendNUIIfChanged({
        openshop = true,
        vehiclesdata = vehiclebysell,
        vehicleCategorys = category,
        colorlist = Config['ColorList'],
        vehicleimages = Config.VehicleImages or {},
        money = GetMoney(),
        bank = GetBank(),
        shop = shop
    })

    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
    ValDev.openfocus = true
    nuiState.open = true
end

RegisterCommand('dbv', function()
    SetNuiFocusKeepInput(true)
    SetNuiFocus(false, false)
end)

RegisterNUICallback('openfocus', function()
    if ValDev.IsInShopMenu then
        local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
        num = num + 1
        if num > 4 then num = 1 end
        SetVehicleCam(vehicle, num)
    end
end)

RegisterNUICallback('rotate360', function(data)
    if not ValDev.IsInShopMenu then return end

    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    if DoesEntityExist(vehicle) then
        local currentHeading = GetEntityHeading(vehicle)
        local rotationSpeed = 0.3
        SetEntityHeading(vehicle, currentHeading - (data.deltaX * rotationSpeed))
    end
end)

RegisterNUICallback('testcar', function(data)
    if ValDev.testcarme then return end

    if cam then
        DestroyCam(cam, false)
        RenderScriptCams(false, false, 0, true, true)
        cam = nil
        num = 0
    end

    TriggerServerEvent(Val .. ':Vehicle:Test', data.carname)
end)

local function EndTestDriveSession()
    local playerPed = PlayerPedId()
    local current = GetPlayersLastVehicle(playerPed, true)
    if current and current ~= 0 and DoesEntityExist(current) then
        ESX.Game.DeleteVehicle(current)
    end

    DoScreenFadeOut(500)
    local timeoutAt = GetGameTimer() + 2500
    while not IsScreenFadedOut() and GetGameTimer() < timeoutAt do
        Wait(50)
    end

    TriggerServerEvent(Val .. ':ExitTest')
    SendNUIMessage({ closetime = true })

    local config = Config['ZONE_SHOP'][ValDev.indexshop]
    if config and config.ShopEnterShop and config.ShopEnterShop.Pos then
        pcall(function() exports['Val_report']:PlayerBypassTPM() end)
        SetEntityCoords(playerPed, config.ShopEnterShop.Pos.x, config.ShopEnterShop.Pos.y, config.ShopEnterShop.Pos.z + 1.0)
        Wait(500)
    end

    DoScreenFadeIn(600)
    ValDev.testcarme = false
end

RegisterNetEvent(Val .. ':TestCar:Client')
AddEventHandler(Val .. ':TestCar:Client', function(car)
    if ValDev.testcarme then return end

    local config = Config['ZONE_SHOP'][ValDev.indexshop]
    local playerPed = PlayerPedId()
    ValDev.IsInShopMenu = false

    setHudShopState()
    DeleteShopInsideVehicles()
    ESX.Game.SpawnVehicle(Config['vehicles'][car].model, config.ShopOutside.Pos, config.ShopOutside.Pos.w, function(vehicle)
        TaskWarpPedIntoVehicle(playerPed, vehicle, -1)
        SetVehicleNumberPlateText(vehicle, 'PLAY')
        SetNuiFocus(false, false)
        SetNuiFocusKeepInput(false)
        ValDev.openfocus = false
        SendNUIMessage({ closeui = true })
    end)

    FreezeEntityPosition(playerPed, false)
    SetEntityVisible(playerPed, true)
    SendNUIMessage({ testcar = true, time = 15, carname = Config['vehicles'][car].name })
    TestCarCheck()
end)

function TestCarCheck()
    ValDev.testcarme = true
    while ValDev.testcarme do
        Citizen.Wait(1000)
        if not IsPedInAnyVehicle(PlayerPedId(), false) then
            EndTestDriveSession()
        end
    end
end

RegisterNUICallback('timeouttest', function()
    if ValDev.testcarme then EndTestDriveSession() end
end)

function CheckTestCar()
    return ValDev.testcarme
end

RegisterCommand('ls', function()
    if ValDev.testcarme then
        exports.mechanic_car:MenuMechanic()
    end
end)

exports('CheckTestCar', CheckTestCar)

RegisterNUICallback('buycar', function(data)
    local playerPed = PlayerPedId()
    local selected = Config['vehicles'][data.carname]
    if not selected then return end

    ESX.TriggerServerCallback(Val .. ':buyVehicle', function(hasEnoughMoney)
        if not hasEnoughMoney then
            if data.payment == 'bank' then
                notifyError()
                ExitShopUI()
            else
                Notify('คุณไม่มีเงิน', 'error')
            end
            return
        end

        ValDev.IsInShopMenu = false
        DeleteShopInsideVehicles()

        local config = Config['ZONE_SHOP'][ValDev.indexshop]
        ESX.Game.SpawnVehicle(selected.model, config.ShopOutside.Pos, config.ShopOutside.Pos.w, function(vehicle)
            TaskWarpPedIntoVehicle(playerPed, vehicle, -1)
            local newPlate = GeneratePlate()

            if data.color1 ~= nil then
                local colorcar = Config['ColorList'][1][data.color1]
                if colorcar then
                    SetVehicleCustomPrimaryColour(vehicle, colorcar.r, colorcar.g, colorcar.b)
                else
                    SetVehicleCustomPrimaryColour(vehicle, 93, 182, 229)
                end
            end

            if data.color2 ~= nil then
                local colorcar2 = Config['ColorList'][2][data.color2]
                if colorcar2 then
                    SetVehicleCustomSecondaryColour(vehicle, colorcar2.r, colorcar2.g, colorcar2.b)
                else
                    SetVehicleCustomSecondaryColour(vehicle, 93, 182, 229)
                end
            end

            local vehicleProps = ESX.Game.GetVehicleProperties(vehicle)
            vehicleProps.plate = newPlate
            SetVehicleNumberPlateText(vehicle, newPlate)

            SendNUIMessage({ closeui = true })
            SetNuiFocus(false, false)
            SetNuiFocusKeepInput(false)
            ValDev.openfocus = false

            local job = selected.category
            local carLabel = selected.name or selected.model
            local purchaseModel = selected.model
            if job == 'ambulance' or job == 'police' or job == 'council' then
                TriggerServerEvent(Val .. ':setVehicleOwned', vehicleProps, job, carLabel, purchaseModel)
            else
                TriggerServerEvent(Val .. ':setVehicleOwned', vehicleProps, nil, carLabel, purchaseModel)
            end

            local sendToDiscord = (GetPlayerName(PlayerId()) .. ' ซื้อรถ ' .. selected.model .. ' ทะเบียน ' .. vehicleProps.plate .. ' ราคา ' .. ESX.Math.GroupDigits(selected.price) .. '$')
            TriggerServerEvent('Val_serverlogs:sendToDiscord', 'BuyVehicle', sendToDiscord, GetPlayerServerId(PlayerId()), '^2')
            if selected.price > 650000 then
                TriggerServerEvent('Val_serverlogs:sendToDiscord', 'over_buycar', sendToDiscord, GetPlayerServerId(PlayerId()), '^2')
            end

            setHudShopState()
            Notify(('คุณได้ซื้อรถ %s ทะเบียน %s'):format(carLabel, vehicleProps.plate), 'success')
            TriggerServerEvent(Val .. ':logVehiclePurchase', purchaseModel, vehicleProps.plate)
        end)

        FreezeEntityPosition(playerPed, false)
        SetEntityVisible(playerPed, true)

        if cam then
            DestroyCam(cam, false)
            RenderScriptCams(false, false, 0, true, true)
            cam = nil
            num = 0
        end
    end, selected.model, selected.price, data.payment)
end)

RegisterNUICallback('choosecar', function(data)
    local config = Config['ZONE_SHOP'][ValDev.indexshop]
    local playerPed = PlayerPedId()

    DeleteShopInsideVehicles()
    WaitForVehicleToLoad(data.model)

    ESX.Game.SpawnLocalVehicle(data.model, config.ShopInside.Pos, config.ShopInside.Pos.w, function(vehicle)
        ValDev.LastVehicles[#ValDev.LastVehicles + 1] = vehicle
        TaskWarpPedIntoVehicle(playerPed, vehicle, -1)
        FreezeEntityPosition(vehicle, true)
        SetModelAsNoLongerNeeded(data.model)

        if num == 0 then
            Wait(50)
            local currentVehicle = GetVehiclePedIsIn(PlayerPedId(), false)
            num = 1
            SetVehicleCam(currentVehicle, num)
        end
    end)
end)

RegisterNUICallback('choosecolor1', function(data)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    local color = Config['ColorList'][1][data.color]
    if color then
        SetVehicleCustomPrimaryColour(vehicle, color.r, color.g, color.b)
    end
end)

RegisterNUICallback('choosecolor2', function(data)
    local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
    local color = Config['ColorList'][2][data.color]
    if color then
        SetVehicleCustomSecondaryColour(vehicle, color.r, color.g, color.b)
    end
end)

RegisterNUICallback('quit', function()
    ExitShopUI()
end)

function CheckInShopCar()
    return ValDev.IsInShopMenu
end

exports('CheckInShopCar', CheckInShopCar)

RegisterNetEvent(Val .. ':Garage:SyncOwnedVehicle')
AddEventHandler(Val .. ':Garage:SyncOwnedVehicle', function(garageVehicle)
    if GetResourceState('APEX-Garage') ~= 'started' then return end
    if type(garageVehicle) ~= 'table' then return end
    TriggerEvent('APEX-Garage:addVehicle', garageVehicle)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end

    if ValDev.testcarme then
        TriggerServerEvent(Val .. ':ExitTest')
    end

    if ValDev.IsInShopMenu then
        DeleteShopInsideVehicles()
        local playerPed = PlayerPedId()
        FreezeEntityPosition(playerPed, false)
        SetEntityVisible(playerPed, true)

        local config = Config['ZONE_SHOP'][ValDev.indexshop]
        if config and config.ShopEnterShop and config.ShopEnterShop.Pos then
            pcall(function() exports['Val_report']:PlayerBypassTPM() end)
            SetEntityCoords(playerPed, config.ShopEnterShop.Pos.x, config.ShopEnterShop.Pos.y, config.ShopEnterShop.Pos.z)
        end
    end
end)
