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
	while #ValDev.LastVehicles > 0 do
		local vehicle = ValDev.LastVehicles[1]
		ESX.Game.DeleteVehicle(vehicle)
		table.remove(ValDev.LastVehicles, 1)
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
	local job = ESX.GetPlayerData().job.name
	local grade = ESX.GetPlayerData().job.grade
	local data = {}
	local data2 = {}
	for k,v in pairs(Config["Category"]) do 
		if v.index == 'ambulance' and job == 'ambulance'  then 
			
			table.insert( data, {
				label = v.label,
				index = v.index,
			})
		elseif v.index == 'police' and job == 'police' then 
			table.insert( data, {
				label = v.label,
				index = v.index,
			})
		elseif v.index == 'council' and job == 'council' then 
			table.insert( data, {
				label = v.label,
				index = v.index,
			})
		elseif v.index == 'mcclub' and CheckCount('card_mc') > 0 then 
			table.insert( data, {
				label = v.label,
				index = v.index,
			})
		elseif v.index == 'gang' and CheckCount('card_gang') > 0 then 
			table.insert( data, {
				label = v.label,
				index = v.index,
			})
		else
			if v.index ~= 'ambulance' and v.index ~= 'police' and v.index ~= 'council' and v.index ~= 'mcclub' and v.index ~= 'gang' then 
			
				table.insert( data, {
					label = v.label,
					index = v.index,
				})
			end
		end
	end
	local das = vehiclesByCategory
	for k,v in pairs(das) do 
		for a,b in pairs(das[k]) do 
			if k == 'ambulance' and job == 'ambulance' and grade >= b.grade  then 
				
				if not data2[k] then  
					data2[k] = {}
				end
				table.insert( data2[k], b )
			elseif k == 'police' and job == 'police' and grade >= b.grade then 
				if not data2[k] then  
					data2[k] = {}
				end
				table.insert( data2[k], b )
			elseif k == 'council' and job == 'council' and grade >= b.grade then 
				if not data2[k] then  
					data2[k] = {}
				end
				table.insert( data2[k], b )
			elseif k == 'mcclub' and CheckCount('card_mc') > 0 then 
				if not data2[k] then  
					data2[k] = {}
				end
				table.insert( data2[k], b )
			elseif k == 'gang' and CheckCount('card_gang') > 0 then 
				if not data2[k] then  
					data2[k] = {}
				end
				table.insert( data2[k], b )
			else
				if k ~= 'ambulance' and k ~= 'police' and k ~= 'council' and k ~= 'mcclub' and k ~= 'gang' then 
					if not data2[k] then  
						data2[k] = {}
					end
					table.insert( data2[k], b )
				end
			end
		end
	end
	
	return data,data2
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
