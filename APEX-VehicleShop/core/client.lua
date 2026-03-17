
ESX	= nil

Val = GetCurrentResourceName()
ValDev = {}
ValDev.indexshop = nil

ValDev.IsInShopMenu = false

ValDev.Categories = {}
ValDev.Vehicles = {}
ValDev.LastVehicles = {}

ValDev.openfocus = false
ValDev.testcarme = false

cam = nil
local num = 0

local ClientModules = VehicleShopClientModules or {}
local ClientUi = ClientModules.UI or {}

Citizen.CreateThread(function()
	while ESX == nil do
		TriggerEvent(Config["BaseServer"]["clinet_shared_obj"], function(obj) ESX = obj end)
		Citizen.Wait(10)
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
		if ClientUi.notifyByProvider and ClientUi.notifyByProvider(ConfigNotify, ESX, msg, level) then
			return
		end
		ESX.ShowNotification(msg)
		return
	end

	if ClientUi.notifyByProvider and ClientUi.notifyByProvider(ConfigNotify, ESX, msg, level) then
		return
	end
end


local function notifyError()
    exports[(ConfigNotify and ConfigNotify.SsrResource) or 'ssr_notify']:sendAlert({
        title = 'ร้านรถ',
        msg = 'คุณมีเงินในธนาคารไม่เพียงพอ',
        type = 'error'
    })
end

local function ExitShopUI()
	if not ValDev.IsInShopMenu then return end
	if EnableKeyInShop then
		EnableKeyInShop()
	end
	ExecuteCommand('hud')
	ExecuteCommand('closeminimap')
	ExecuteCommand('closehudspeed')
	DeleteShopInsideVehicles()
	local playerPed = PlayerPedId()
	FreezeEntityPosition(playerPed, false)
	SetEntityVisible(playerPed, true)
	local config = Config['ZONE_SHOP'][ValDev.indexshop]
	pcall(function()
		exports["Val_report"]:PlayerBypassTPM()
	end)
	SetEntityCoords(playerPed, config.ShopEnterShop.Pos.x, config.ShopEnterShop.Pos.y, config.ShopEnterShop.Pos.z)
	SetNuiFocus(false, false)
	SetNuiFocusKeepInput(false)
	SendNUIMessage({ closeui = true })
	ValDev.IsInShopMenu = false
	ValDev.openfocus = false
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
AddEventHandler('esx:setJob', function (job)
	ESX.PlayerData.job = job
end)

CreateThread(function()
    for k, v in pairs(Config["Category"]) do
		table.insert(ValDev.Categories, {name = v.index, label = v.label})
	end
	for k,v in pairs(Config["vehicles"]) do
		for cat,rat in pairs(Config["Category"]) do
			if Config["vehicles"][k]["category"] == rat.index then
				
				table.insert(ValDev.Vehicles, {name = v.name, model = v.model, price =v.price, category = v.category,kg = v.kg,grade = v.grade,typecar = v.typecar,class = GetClassNameCar(v.model)})
			end
		end
	end
end)

CreateThread(function()
	local function toVec3(pos)
		if not pos then return nil end
		local x, y, z = pos.x, pos.y, pos.z
		if x == nil or y == nil or z == nil then
			return nil
		end
		return vector3(x + 0.0, y + 0.0, z + 0.0)
	end

	local zoneCache = {}
	for k, v in pairs(Config['ZONE_SHOP']) do
		local enterPos = toVec3(v.ShopEnterShop and v.ShopEnterShop.Pos)

		zoneCache[#zoneCache + 1] = {
			index = k,
			shop = v.shop,
			enter = v.ShopEnterShop,
			enterPos = enterPos
		}
	end

	while true do
		local sleep = 1250

		if not ValDev.IsInShopMenu then
			local player = PlayerPedId()
			local coords = toVec3(GetEntityCoords(player))
			if not coords then
				Wait(500)
				goto CONTINUE_MAIN_LOOP
			end
			local nearestIndex, nearestShop, nearestDistance = nil, nil, math.huge

			for i = 1, #zoneCache do
				local zone = zoneCache[i]
				local enter = zone.enter
				local enterPos = zone.enterPos
				if not enterPos then
					goto CONTINUE_ZONE
				end

				local distance = #(coords - enterPos)

				if distance < nearestDistance then
					nearestDistance = distance
					nearestIndex = zone.index
					nearestShop = zone.shop
				end

				if enter.Type ~= -1 and distance < Config.DrawDistance then
					DrawMarker(enter.Type, enterPos.x, enterPos.y, enterPos.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, enter.Size.x, enter.Size.y, enter.Size.z, enter.colormarker.r, enter.colormarker.g, enter.colormarker.b, enter.colormarker.a, false, true, 2, false, false, false, false)
					sleep = 50
				end

				::CONTINUE_ZONE::
			end

			if nearestIndex ~= nil then
				ValDev.indexshop = nearestIndex
				if nearestDistance <= 2.0 then
					sleep = 0
					if IsControlJustReleased(0, 38) then
						OpenShopMenu(nearestShop, nearestIndex)
					end
				elseif nearestDistance <= (Config.DrawDistance + 25.0) then
					sleep = math.min(sleep, 300)
				end
			end
		else
			sleep = 1000
		end

		::CONTINUE_MAIN_LOOP::
		Wait(sleep)
	end
end)


function OpenShopMenu(shop,indexshop)
	TriggerServerEvent(Val..':ExitTest')
	ValDev.IsInShopMenu = true
	ExecuteCommand('hud')
	ExecuteCommand('closeminimap')
	ExecuteCommand('closehudspeed')
	DisableKeyInShop()
	local playerPed = PlayerPedId()
	FreezeEntityPosition(playerPed, true)
	SetEntityVisible(playerPed, false)
	local config = Config['ZONE_SHOP'][indexshop]
	pcall(function()
        exports["Val_report"]:PlayerBypassTPM()
    end)
	SetEntityCoords(playerPed, config.ShopEnterShop.Pos.x, config.ShopEnterShop.Pos.y, config.ShopEnterShop.Pos.z)
	local vehiclesByCategory = {}
	for i=1, #ValDev.Categories, 1 do
		vehiclesByCategory[ValDev.Categories[i].name] = {}
	end
	for i=1, #ValDev.Vehicles, 1 do
		if IsModelInCdimage(GetHashKey(ValDev.Vehicles[i].model)) then
			table.insert(vehiclesByCategory[ValDev.Vehicles[i].category], ValDev.Vehicles[i])
		end
	end	
	local category,vehiclebysell = GetCategory(vehiclesByCategory)
	
	SendNUIMessage({
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
end

-- RegisterKeyMapping('openfocus', 'openfocus', 'keyboard', 'H')
-- RegisterCommand('openfocus', function(source,arg)
-- 	if ValDev.IsInShopMenu then 
-- 		if not ValDev.openfocus then 
-- 			ValDev.openfocus = true
-- 			Wait(500)
-- 			SetNuiFocus(true, true)
-- 			SetNuiFocusKeepInput(false)
-- 		else
-- 			ValDev.openfocus = false
-- 			Wait(500)
-- 			SetNuiFocus(true, true)
-- 			SetNuiFocusKeepInput(false)
-- 		end
-- 	end
-- end,false)

RegisterCommand('dbv', function()
	SetNuiFocusKeepInput(true)
	SetNuiFocus(false, false)
end)

RegisterNUICallback('openfocus', function()
	if ValDev.IsInShopMenu then 
		local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
		num = num + 1
		if num > 4 then 
			num = 1
		end
		SetVehicleCam(vehicle, num)
	end
end)

-- 360 Degree Rotation - Left Click Drag
RegisterNUICallback('rotate360', function(data)
	if ValDev.IsInShopMenu then
		local vehicle = GetVehiclePedIsIn(PlayerPedId(), false)
		if DoesEntityExist(vehicle) then
			local currentHeading = GetEntityHeading(vehicle)
			local rotationSpeed = 0.3
			local newHeading = currentHeading - (data.deltaX * rotationSpeed)
			SetEntityHeading(vehicle, newHeading)
		end
	end
end)





RegisterNUICallback('testcar', function(data)
	if not ValDev.testcarme then
		if cam then
			DestroyCam(cam, false)
			RenderScriptCams(false, false, 0, true, true)
			cam = nil
			num = 0
		end 
		TriggerServerEvent(Val..':Vehicle:Test', data.carname)
	end
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

	TriggerServerEvent(Val..':ExitTest')
	SendNUIMessage({
		closetime = true
	})

	local config = Config['ZONE_SHOP'][ValDev.indexshop]
	if config and config.ShopEnterShop and config.ShopEnterShop.Pos then
		pcall(function()
			exports["Val_report"]:PlayerBypassTPM()
		end)
		SetEntityCoords(playerPed, config.ShopEnterShop.Pos.x, config.ShopEnterShop.Pos.y, config.ShopEnterShop.Pos.z + 1.0)
		Wait(500)
	end

	DoScreenFadeIn(600)
	ValDev.testcarme = false
end

RegisterNetEvent(Val..':TestCar:Client')
AddEventHandler(Val..':TestCar:Client', function(car)
	if not ValDev.testcarme then
		local config = Config['ZONE_SHOP'][ValDev.indexshop]
		local playerPed = PlayerPedId()
		ValDev.IsInShopMenu = false
		ExecuteCommand('hud')
		ExecuteCommand('closeminimap')
		ExecuteCommand('closehudspeed')
		DeleteShopInsideVehicles()
		ESX.Game.SpawnVehicle(Config["vehicles"][car].model, config.ShopOutside.Pos, config.ShopOutside.Pos.w, function (vehicle)
			TaskWarpPedIntoVehicle(playerPed, vehicle, -1)
			SetVehicleNumberPlateText(vehicle, 'PLAY')
			SetNuiFocus(false, false)
			SetNuiFocusKeepInput(false)
			ValDev.openfocus = false
			SendNUIMessage({
				closeui = true
			})
		end)
		FreezeEntityPosition(playerPed, false)
		SetEntityVisible(playerPed, true)
		SendNUIMessage({
			testcar = true,
			time = 15,
			carname = Config["vehicles"][car].name
		})
		TestCarCheck()
	end
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
	if not ValDev.testcarme then return end
	EndTestDriveSession()
end)

function CheckTestCar()
	return ValDev.testcarme
end
RegisterCommand('ls', function()
	if ValDev.testcarme then 
		exports.mechanic_car:MenuMechanic()
	end
end)
exports("CheckTestCar", CheckTestCar)

RegisterNUICallback('buycar', function(data)
	local playerPed   = PlayerPedId()

	ESX.TriggerServerCallback(Val..':buyVehicle', function (hasEnoughMoney)
		if hasEnoughMoney then
			ValDev.IsInShopMenu = false
			DeleteShopInsideVehicles()
			local config = Config['ZONE_SHOP'][ValDev.indexshop]
			ESX.Game.SpawnVehicle(Config["vehicles"][data.carname].model, config.ShopOutside.Pos, config.ShopOutside.Pos.w, function (vehicle)
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
				SendNUIMessage({
					closeui = true
				})
				SetNuiFocus(false, false)
				SetNuiFocusKeepInput(false)
				ValDev.openfocus = false
				local job = Config["vehicles"][data.carname].category
				local carLabel = Config["vehicles"][data.carname].name or Config["vehicles"][data.carname].model
				local purchaseModel = Config["vehicles"][data.carname].model
				if job == 'ambulance' or job == 'police' or job == 'council' then
					TriggerServerEvent(Val..':setVehicleOwned', vehicleProps, job, carLabel, purchaseModel)
				else
					TriggerServerEvent(Val..':setVehicleOwned', vehicleProps, nil, carLabel, purchaseModel)
				end


				local sendToDiscord = '' .. GetPlayerName(PlayerId()) .. ' ซื้อรถ ' .. Config["vehicles"][data.carname].model .. ' ทะเบียน ' .. vehicleProps.plate .. ' ราคา ' .. ESX.Math.GroupDigits(Config["vehicles"][data.carname].price) ..'$'
				TriggerServerEvent('Val_serverlogs:sendToDiscord', 'BuyVehicle', sendToDiscord, GetPlayerServerId(PlayerId()), '^2')
				if Config["vehicles"][data.carname].price > 650000 then 
					local sendToDiscord2 = '' .. GetPlayerName(PlayerId()) .. ' ซื้อรถ ' .. Config["vehicles"][data.carname].model .. ' ทะเบียน ' .. vehicleProps.plate .. ' ราคา ' .. ESX.Math.GroupDigits(Config["vehicles"][data.carname].price) ..'$'
					TriggerServerEvent('Val_serverlogs:sendToDiscord', 'over_buycar', sendToDiscord2, GetPlayerServerId(PlayerId()), '^2')
				end
				ExecuteCommand('hud')
				ExecuteCommand('closeminimap')
				ExecuteCommand('closehudspeed')
				Notify(('คุณได้ซื้อรถ %s ทะเบียน %s'):format(carLabel, vehicleProps.plate), 'success')
				TriggerServerEvent(Val..':logVehiclePurchase', Config["vehicles"][data.carname].model, vehicleProps.plate)
			end)
			FreezeEntityPosition(playerPed, false)
			SetEntityVisible(playerPed, true)
			if cam then
				DestroyCam(cam, false)
				RenderScriptCams(false, false, 0, true, true)
				cam = nil
				num = 0
			end
		else
			if data.payment == 'bank' then
				notifyError()
				ExitShopUI()
			else
				Notify('คุณไม่มีเงิน', 'error')
			end
		end
	end,Config["vehicles"][data.carname].model,Config["vehicles"][data.carname].price,data.payment)
end)

RegisterNUICallback('choosecar', function(data)
	local config = Config['ZONE_SHOP'][ValDev.indexshop]
	local playerPed   = PlayerPedId()
	DeleteShopInsideVehicles()
	WaitForVehicleToLoad(data.model)

	ESX.Game.SpawnLocalVehicle(data.model, config.ShopInside.Pos, config.ShopInside.Pos.w, function (vehicle)
		table.insert(ValDev.LastVehicles, vehicle)
		TaskWarpPedIntoVehicle(playerPed, vehicle, -1)
		FreezeEntityPosition(vehicle, true)
		SetModelAsNoLongerNeeded(data.model)
		if num == 0 then
			Wait(50)
			local vehicle       = GetVehiclePedIsIn(PlayerPedId(), false)
			num = num + 1
			if num > 4 then 
				num = 1
			end
			SetVehicleCam(vehicle, num)
		end
	end)
	
	
	

end)

RegisterNUICallback('choosecolor1', function(data)
	local vehicle       = GetVehiclePedIsIn(PlayerPedId(), false)
	local color = Config['ColorList'][1][data.color]
	if color then
		SetVehicleCustomPrimaryColour(vehicle, color.r, color.g, color.b)
	end
	
end)

RegisterNUICallback('choosecolor2', function(data)
	local vehicle       = GetVehiclePedIsIn(PlayerPedId(), false)
	local color2 = Config['ColorList'][2][data.color]
	if color2 then
		SetVehicleCustomSecondaryColour(vehicle, color2.r, color2.g, color2.b)
	end
end)

RegisterNUICallback('quit', function()
	ExitShopUI()
end)

function CheckInShopCar()
	return ValDev.IsInShopMenu
end
exports("CheckInShopCar", CheckInShopCar)


RegisterNetEvent(Val..':Garage:SyncOwnedVehicle')
AddEventHandler(Val..':Garage:SyncOwnedVehicle', function(garageVehicle)
	if GetResourceState('APEX-Garage') ~= 'started' then return end
	if type(garageVehicle) ~= 'table' then return end
	TriggerEvent('APEX-Garage:addVehicle', garageVehicle)
end)

AddEventHandler('onResourceStop', function(resource)
	if resource == GetCurrentResourceName() then
		if ValDev.testcarme then
			TriggerServerEvent(Val..':ExitTest')
		end

		if ValDev.IsInShopMenu then
			DeleteShopInsideVehicles()
			local playerPed = PlayerPedId()
			FreezeEntityPosition(playerPed, false)
			SetEntityVisible(playerPed, true)
			local config = Config['ZONE_SHOP'][ValDev.indexshop]
			if config and config.ShopEnterShop and config.ShopEnterShop.Pos then
				pcall(function()
					exports["Val_report"]:PlayerBypassTPM()
				end)
				SetEntityCoords(playerPed, config.ShopEnterShop.Pos.x, config.ShopEnterShop.Pos.y, config.ShopEnterShop.Pos.z)
			end
		end
	end
end)
