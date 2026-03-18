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


local function normalizeJobName(jobName)
	if jobName == nil then
		return ''
	end

	return tostring(jobName)
end

function ShopVisibleForPlayer(shopConfig)
	if type(shopConfig) ~= 'table' then
		return false
	end

	local visibleJobs = shopConfig.visibleJobs
	if visibleJobs == nil then
		return true
	end

	local playerData = ESX.GetPlayerData() or {}
	local jobData = playerData.job or {}
	local playerJob = normalizeJobName(jobData.name)

	if type(visibleJobs) == 'string' then
		return playerJob == normalizeJobName(visibleJobs)
	end

	if type(visibleJobs) == 'table' then
		for i = 1, #visibleJobs do
			if playerJob == normalizeJobName(visibleJobs[i]) then
				return true
			end
		end
	end

	return false
end

local function appendVehicleSource(target, source)
	if type(source) ~= 'table' then
		return
	end

	for key, vehicleConfig in pairs(source) do
		target[tostring(key)] = vehicleConfig
	end
end

function GetVehiclePoolBySource(sourceName)
	local vehicles = {}
	local sourceType = tostring(sourceName or 'public')

	if sourceType == 'job' then
		appendVehicleSource(vehicles, Config['JobVehicles'])
	elseif sourceType == 'all' then
		appendVehicleSource(vehicles, Config['vehicles'])
		appendVehicleSource(vehicles, Config['JobVehicles'])
	else
		appendVehicleSource(vehicles, Config['vehicles'])
	end

	return vehicles
end


function GetVehicleFromShop(shopConfig, vehicleKeyOrModel)
	local shopVehicles = GetVehiclesForShop(shopConfig)
	local lookupKey = tostring(vehicleKeyOrModel or '')
	if lookupKey == '' then
		return nil
	end

	local direct = shopVehicles[lookupKey]
	if direct then
		return direct
	end

	for _, vehicleConfig in pairs(shopVehicles) do
		if vehicleConfig and tostring(vehicleConfig.model or '') == lookupKey then
			return vehicleConfig
		end
	end

	return nil
end

function GetVehiclesForShop(shopConfig)
	if type(shopConfig) ~= 'table' then
		return GetVehiclePoolBySource('public')
	end

	local vehiclePool = GetVehiclePoolBySource(shopConfig.vehicleSource)
	if shopConfig.vehicleList == nil then
		return vehiclePool
	end

	local selectedVehicles = {}
	local configuredList = shopConfig.vehicleList

	if type(configuredList) == 'table' then
		for i = 1, #configuredList do
			local vehicleKey = tostring(configuredList[i])
			local vehicleConfig = vehiclePool[vehicleKey]
			if vehicleConfig then
				selectedVehicles[vehicleKey] = vehicleConfig
			end
		end
	end

	return selectedVehicles
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


function GetCategory(vehiclesByCategory, availableCategories)
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
		local hasVehiclesInShop = availableCategories == nil or availableCategories[v.index] == true
		if hasVehiclesInShop then
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
	end

	for category, vehicles in pairs(vehiclesByCategory) do
		for i = 1, #vehicles do
			local vehicle = vehicles[i]
			local allowed = false
			local canBuy = true
			local requiredGrade = tonumber(vehicle.grade) or 0
			if category == 'ambulance' then
				allowed = job == 'ambulance'
				canBuy = grade >= requiredGrade
			elseif category == 'police' then
				allowed = job == 'police'
				canBuy = grade >= requiredGrade
			elseif category == 'council' then
				allowed = job == 'council'
				canBuy = grade >= requiredGrade
			elseif category == 'mcclub' then
				allowed = hasMc
			elseif category == 'gang' then
				allowed = hasGang
			else
				allowed = true
			end

			if allowed then
				data2[category] = data2[category] or {}
				local vehicleEntry = {}
				for key, value in pairs(vehicle) do
					vehicleEntry[key] = value
				end
				vehicleEntry.requiredGrade = requiredGrade
				vehicleEntry.canBuy = canBuy
				table.insert(data2[category], vehicleEntry)
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
