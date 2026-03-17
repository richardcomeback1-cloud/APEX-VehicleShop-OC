local shopControlActive = false
local shopControlThreadStarted = false

local ClientModules = VehicleShopClientModules or {}
local ClientInventory = ClientModules.Inventory or {}
local ClientEconomy = ClientModules.Economy or {}

local function ensureShopControlThread()
	if shopControlThreadStarted then return end
	shopControlThreadStarted = true

	CreateThread(function()
		while true do
			local sleep = 1000
			if shopControlActive and ValDev.IsInShopMenu then
				sleep = 0
				DisableControlAction(0, 75, true)
				DisableControlAction(27, 75, true)
				DisplayRadar(false) -- กัน minimap โผล่ตอนนั่งรถพรีวิวในร้าน
			end
			Wait(sleep)
		end
	end)
end

function DeleteShopInsideVehicles()
	for i = #ValDev.LastVehicles, 1, -1 do
		local vehicle = ValDev.LastVehicles[i]
		ESX.Game.DeleteVehicle(vehicle)
		ValDev.LastVehicles[i] = nil
	end
end

function DisableKeyInShop()
	shopControlActive = true
	ensureShopControlThread()
end

function EnableKeyInShop()
	shopControlActive = false
end

function WaitForVehicleToLoad(modelHash)
	modelHash = (type(modelHash) == 'number' and modelHash or GetHashKey(modelHash))
	if not HasModelLoaded(modelHash) then
		RequestModel(modelHash)
		BeginTextCommandBusyString('STRING')
		AddTextComponentSubstringPlayerName('the vehicle is currently loading, please wait')
		EndTextCommandBusyString(4)
		while not HasModelLoaded(modelHash) do
			Citizen.Wait(1)
			DisableAllControlActions(0)
		end
		RemoveLoadingPrompt()
	end
end

CheckCount = function(item_name)
	if ClientInventory.countItem then
		return ClientInventory.countItem(ESX, item_name)
	end
	return 0
end

function GetMoney()
	if ClientEconomy.getCash then
		return ClientEconomy.getCash(ESX)
	end
	return 0
end


function GetBank()
	if ClientEconomy.getBank then
		return ClientEconomy.getBank(ESX)
	end
	return 0
end

function GetClassNameCar(model)
    local typeClass = GetVehicleClassFromName(model) 
    return Config['Class_Vehicle'][typeClass] or 'NULL'
end

Citizen.CreateThread(function()
	RequestIpl('shr_int')
	local interiorID = 7170
	LoadInterior(interiorID)
	EnableInteriorProp(interiorID, 'csr_beforeMission')
	RefreshInterior(interiorID)
end)


function GetCategory(vehiclesByCategory)
	local playerData = ESX.GetPlayerData() or {}
	local jobData = playerData.job or {}
	local job = jobData.name
	local grade = tonumber(jobData.grade) or 0
	local cardMcCount = CheckCount('card_mc')
	local cardGangCount = CheckCount('card_gang')
	local hasMc = cardMcCount > 0
	local hasGang = cardGangCount > 0
	local data = {}
	local data2 = {}

	for _, v in pairs(Config["Category"]) do
		local allowed = false
		if v.index == 'ambulance' then
			allowed = job == 'ambulance'
		elseif v.index == 'police' then
			allowed = job == 'police'
		elseif v.index == 'council' then
			allowed = job == 'council'
		elseif v.index == 'mcclub' then
			allowed = hasMc
		elseif v.index == 'gang' then
			allowed = hasGang
		else
			allowed = true
		end

		if allowed then
			data[#data + 1] = { label = v.label, index = v.index }
		end
	end

	for category, vehicles in pairs(vehiclesByCategory) do
		for i = 1, #vehicles do
			local vehicle = vehicles[i]
			local allowed = false
			if category == 'ambulance' then
				allowed = job == 'ambulance' and grade >= (tonumber(vehicle.grade) or 0)
			elseif category == 'police' then
				allowed = job == 'police' and grade >= (tonumber(vehicle.grade) or 0)
			elseif category == 'council' then
				allowed = job == 'council' and grade >= (tonumber(vehicle.grade) or 0)
			elseif category == 'mcclub' then
				allowed = hasMc
			elseif category == 'gang' then
				allowed = hasGang
			else
				allowed = true
			end

			if allowed then
				data2[category] = data2[category] or {}
				table.insert(data2[category], vehicle)
			end
		end
	end

	return data, data2
end


function SetVehicleCam(vehicle, pos)
    if cam then
        DestroyCam(cam, false)
        RenderScriptCams(false, false, 0, true, true)
        cam = nil
    end

    local offset = {
        [1] = vector3(-2.5,  4.5, 1.5),
    	[2] = vector3( 2.5,  4.5, 1.5), 
    	[3] = vector3(-2.5, -4.5, 1.5),
    	[4] = vector3( 2.5, -4.5, 1.5), 
    }

    local coords = GetOffsetFromEntityInWorldCoords(vehicle, offset[pos].x, offset[pos].y, offset[pos].z)

    cam = CreateCam("DEFAULT_SCRIPTED_CAMERA", true)
    SetCamCoord(cam, coords.x, coords.y, coords.z)
    PointCamAtEntity(cam, vehicle, 0.0, 0.0, 0.0, true)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
end
