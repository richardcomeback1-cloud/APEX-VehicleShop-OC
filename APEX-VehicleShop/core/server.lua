local ESX = nil
local Val = GetCurrentResourceName()
local CALLBACK_NAMESPACE = 'APEX-VehicleShop'

local function fetchESX()
    if ESX then return ESX end

    pcall(function()
        ESX = exports['es_extended']:getSharedObject()
    end)

    while ESX == nil do
        TriggerEvent(Config["BaseServer"]["server_shared_obj"], function(obj) ESX = obj end)
        Wait(100)
    end

    return ESX
end

CreateThread(function()
    fetchESX()
end)

local activeTestBuckets = {}
local purchaseTickets = {}
local webhookTickets = {}
local pendingWebhookRequests = {}
local testDriveCooldowns = {}

local PURCHASE_TICKET_TTL_MS = 60 * 1000
local WEBHOOK_TICKET_TTL_MS = 60 * 1000
local TESTDRIVE_COOLDOWN_MS = 5000
local SHOP_INTERACTION_MAX_DISTANCE = tonumber((Config and Config.Security and Config.Security.ShopInteractDistance) or 15.0) or 15.0
local SHOP_SAVE_MAX_DISTANCE = tonumber((Config and Config.Security and Config.Security.ShopSaveDistance) or 40.0) or 40.0
local PLATE_CACHE_TTL_MS = tonumber((Config and Config.Security and Config.Security.PlateCacheTtlMs) or 10000) or 10000
local BUY_COOLDOWN_MS = tonumber((Config and Config.Security and Config.Security.BuyCooldownMs) or 1200) or 1200
local OWNED_SAVE_COOLDOWN_MS = tonumber((Config and Config.Security and Config.Security.SaveOwnedCooldownMs) or 1500) or 1500
local WEBHOOK_WORKER_TICK_MS = tonumber((Config and Config.Security and Config.Security.WebhookWorkerTickMs) or 250) or 250
local WEBHOOK_RETRY_BASE_MS = tonumber((Config and Config.Security and Config.Security.WebhookRetryBaseMs) or 2000) or 2000
local WEBHOOK_RETRY_MAX_MS = tonumber((Config and Config.Security and Config.Security.WebhookRetryMaxMs) or 60000) or 60000
local WEBHOOK_QUEUE_WARN_SIZE = tonumber((Config and Config.Security and Config.Security.WebhookQueueWarnSize) or 200) or 200

local vehicleConfigIndex = nil
local plateTakenCache = {}
local buyCooldowns = {}
local saveOwnedCooldowns = {}
local playerCache = {}
local PLAYER_CACHE_TTL_MS = tonumber((Config and Config.Security and Config.Security.PlayerCacheTtlMs) or 1000) or 1000

local webhookQueue = {}
local webhookQueueHead = 1
local webhookQueueTail = 0
local webhookQueueInFlight = false
local webhookQueueDirty = false
local webhookPersistScheduled = false

local sendPurchaseWebhook
local pruneStateTables
local invalidatePlayerCache
local upsertAttemptIndex = 1

local Modules = VehicleShopModules or {}
local PlayerModule = Modules.Player or {}
local InventoryModule = Modules.Inventory or {}
local EconomyModule = Modules.Economy or {}
local JobsModule = Modules.Jobs or {}
local UiModule = Modules.UI or {}

local function collectShopPoints(shop)
    local points = {}

    local function push(pos)
        if pos and pos.x and pos.y and pos.z then
            points[#points + 1] = vector3(pos.x, pos.y, pos.z)
        end
    end

    push(shop and shop.ShopEnterShop and shop.ShopEnterShop.Pos)
    push(shop and shop.ShopInside and shop.ShopInside.Pos)
    push(shop and shop.ShopOutside and shop.ShopOutside.Pos)

    return points
end

local function findShopInRange(src, maxDistance)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end

    local coords = GetEntityCoords(ped)
    if not coords then return nil end

    local allowedDistance = tonumber(maxDistance) or SHOP_INTERACTION_MAX_DISTANCE
    local nearestShopIndex = nil
    local nearestDistance = nil

    for shopIndex, shop in pairs(Config['ZONE_SHOP'] or {}) do
        local points = collectShopPoints(shop)
        for i = 1, #points do
            local distance = #(coords - points[i])
            if distance <= allowedDistance and (nearestDistance == nil or distance < nearestDistance) then
                nearestDistance = distance
                nearestShopIndex = shopIndex
            end
        end
    end

    return nearestShopIndex
end

local function isPlayerNearAnyShop(src, maxDistance)
    return findShopInRange(src, maxDistance) ~= nil
end

local function leaveTestBucket(src)
    local state = activeTestBuckets[src]
    if not state then return end

    local targetBucket = tonumber(state.previousBucket) or 0
    pcall(function()
        SetPlayerRoutingBucket(src, targetBucket)
    end)

    activeTestBuckets[src] = nil
end


local function clearPlayerState(src)
    leaveTestBucket(src)
    purchaseTickets[src] = nil
    webhookTickets[src] = nil
    pendingWebhookRequests[src] = nil
    testDriveCooldowns[src] = nil
    buyCooldowns[src] = nil
    saveOwnedCooldowns[src] = nil
    invalidatePlayerCache(src)
end

local function enterTestBucket(src)
    local currentBucket = 0
    pcall(function()
        currentBucket = GetPlayerRoutingBucket(src)
    end)

    local isolatedBucket = 50000 + src
    activeTestBuckets[src] = {
        previousBucket = tonumber(currentBucket) or 0,
        currentBucket = isolatedBucket
    }

    SetPlayerRoutingBucket(src, isolatedBucket)
end

local function buildVehicleConfigIndex()
    if vehicleConfigIndex then return vehicleConfigIndex end

    vehicleConfigIndex = {}
    for key, cfg in pairs(Config['vehicles'] or {}) do
        vehicleConfigIndex[tostring(key)] = cfg
        if cfg and cfg.model then
            vehicleConfigIndex[tostring(cfg.model)] = cfg
        end
    end

    return vehicleConfigIndex
end

local function vehCfg(model)
    local idx = buildVehicleConfigIndex()
    return idx[tostring(model)]
end

local function canAfford(xPlayer, payment, amount)
    if EconomyModule.canAfford then
        return EconomyModule.canAfford(xPlayer, payment, amount)
    end
    return false
end

local function removeMoney(xPlayer, payment, amount)
    if EconomyModule.removeMoney then
        EconomyModule.removeMoney(xPlayer, payment, amount)
    end
end

local function normalizePlate(plate)
    local trimmed = tostring(plate or ''):gsub('^%s*(.-)%s*$', '%1')
    return trimmed:upper()
end

local function compactPlate(plate)
    local compacted = normalizePlate(plate):gsub('%s+', '')
    return compacted
end

local function isOnCooldown(map, key, cooldownMs)
    local now = GetGameTimer()
    local readyAt = tonumber(map[key] or 0) or 0
    if now < readyAt then
        return true
    end
    map[key] = now + (tonumber(cooldownMs) or 0)
    return false
end

local function getPlayerCached(src)
    fetchESX()
    if PlayerModule.getCached then
        return PlayerModule.getCached(ESX, src, PLAYER_CACHE_TTL_MS)
    end
    return ESX.GetPlayerFromId(src)
end

invalidatePlayerCache = function(src)
    if PlayerModule.invalidate then
        PlayerModule.invalidate(src)
    end
    playerCache[src] = nil
end

local function getPlateOwnerCached(compact)
    local cached = plateTakenCache[compact]
    local now = GetGameTimer()
    if cached and cached.expiresAt > now then
        return cached.owner
    end

    local ok, row = pcall(function()
        return MySQL.single.await('SELECT owner FROM owned_vehicles WHERE REPLACE(UPPER(plate), " ", "") = ? LIMIT 1', { compact })
    end)

    local owner = nil
    if ok and row and row.owner then
        owner = tostring(row.owner)
    end

    plateTakenCache[compact] = {
        owner = owner,
        expiresAt = now + PLATE_CACHE_TTL_MS
    }

    return owner
end

local function ensureOwnedVehiclesIndex(column, indexName)
    local ok, rows = pcall(function()
        return MySQL.query.await('SHOW INDEX FROM owned_vehicles WHERE Key_name = ?', { indexName })
    end)
    if ok and type(rows) == 'table' and #rows > 0 then
        return
    end

    pcall(function()
        MySQL.query.await(('ALTER TABLE owned_vehicles ADD INDEX %s (%s)'):format(indexName, column))
    end)
end

local function cbIsPlateTaken(source, cb, plate)
    fetchESX()
    pruneStateTables(false)

    local compact = compactPlate(plate)
    if compact == '' then
        cb(false)
        return
    end

    local owner = getPlateOwnerCached(compact)
    cb(owner ~= nil and owner ~= '')
end

local function cbBuyVehicle(source, cb, model, price, payment)
    fetchESX()
    pruneStateTables(false)
    local xPlayer = getPlayerCached(source)
    if not xPlayer then cb(false) return end

    if isOnCooldown(buyCooldowns, source, BUY_COOLDOWN_MS) then
        cb(false)
        return
    end

    local cfg = vehCfg(model)
    if not cfg or not cfg.model then cb(false) return end

    local shopIndex = findShopInRange(source, SHOP_INTERACTION_MAX_DISTANCE)
    if not shopIndex then cb(false) return end

    -- ราคาเชื่อจาก server config เท่านั้น (ห้ามใช้ค่าจาก client)
    local amount = tonumber(cfg.price or 0) or 0
    if amount <= 0 then cb(false) return end

    if JobsModule.canAccessVehicle and (not JobsModule.canAccessVehicle(xPlayer, cfg)) then
        cb(false)
        return
    end

    if not canAfford(xPlayer, payment, amount) then cb(false) return end

    removeMoney(xPlayer, payment, amount)

    local now = GetGameTimer()
    purchaseTickets[source] = {
        model = tostring(cfg.model),
        shopIndex = shopIndex,
        expiresAt = now + PURCHASE_TICKET_TTL_MS
    }

    cb(true)
end

CreateThread(function()
    fetchESX()

    ensureOwnedVehiclesIndex('owner', 'idx_owned_vehicles_owner')
    ensureOwnedVehiclesIndex('plate', 'idx_owned_vehicles_plate')

    ESX.RegisterServerCallback(CALLBACK_NAMESPACE .. ':isPlateTaken', cbIsPlateTaken)
    if Val ~= CALLBACK_NAMESPACE then
        ESX.RegisterServerCallback(Val .. ':isPlateTaken', cbIsPlateTaken)
    end

    ESX.RegisterServerCallback(CALLBACK_NAMESPACE .. ':buyVehicle', cbBuyVehicle)
    if Val ~= CALLBACK_NAMESPACE then
        ESX.RegisterServerCallback(Val .. ':buyVehicle', cbBuyVehicle)
    end
end)

RegisterNetEvent(Val .. ':Vehicle:Test')
AddEventHandler(Val .. ':Vehicle:Test', function(carname)
    fetchESX()

    local src = source
    local cfg = vehCfg(carname)
    if not cfg then return end

    if not findShopInRange(src, SHOP_INTERACTION_MAX_DISTANCE) then return end

    local xPlayer = getPlayerCached(src)
    if not xPlayer then return end

    if JobsModule.canAccessVehicle and (not JobsModule.canAccessVehicle(xPlayer, cfg)) then
        return
    end

    local now = GetGameTimer()
    local nextAllowedAt = testDriveCooldowns[src] or 0
    if now < nextAllowedAt then
        return
    end

    testDriveCooldowns[src] = now + TESTDRIVE_COOLDOWN_MS

    leaveTestBucket(src)
    enterTestBucket(src)

    TriggerClientEvent(Val .. ':TestCar:Client', src, carname)
end)

RegisterNetEvent(Val .. ':ExitTest')
AddEventHandler(Val .. ':ExitTest', function()
    leaveTestBucket(source)
end)

AddEventHandler('playerDropped', function()
    clearPlayerState(source)
    pruneStateTables(true)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    for src in pairs(activeTestBuckets) do
        clearPlayerState(src)
    end
    pruneStateTables(true)
end)

local lastPruneAt = 0
pruneStateTables = function(force)
    local now = GetGameTimer()
    if not force and (now - lastPruneAt) < 2000 then
        return
    end
    lastPruneAt = now

    for src, ticket in pairs(purchaseTickets) do
        if now > (tonumber(ticket.expiresAt) or 0) then
            purchaseTickets[src] = nil
        end
    end

    for src, ticket in pairs(webhookTickets) do
        if now > (tonumber(ticket.expiresAt) or 0) then
            webhookTickets[src] = nil
        end
    end

    for src, request in pairs(pendingWebhookRequests) do
        if now > (tonumber(request.expiresAt) or 0) then
            pendingWebhookRequests[src] = nil
        end
    end

    for compact, data in pairs(plateTakenCache) do
        if not data or now > (tonumber(data.expiresAt) or 0) then
            plateTakenCache[compact] = nil
        end
    end

    for src, readyAt in pairs(buyCooldowns) do
        if now > ((tonumber(readyAt) or 0) + 15000) then
            buyCooldowns[src] = nil
        end
    end

    for src, readyAt in pairs(saveOwnedCooldowns) do
        if now > ((tonumber(readyAt) or 0) + 15000) then
            saveOwnedCooldowns[src] = nil
        end
    end

    if PlayerModule.prune then
        PlayerModule.prune()
    else
        for src, cached in pairs(playerCache) do
            if not cached or now > (tonumber(cached.expiresAt) or 0) then
                playerCache[src] = nil
            end
        end
    end
end

local function upsertOwnedVehicle(identifier, plate, vehicleJson, vehicleType, jobName, vehicleName, healthVehicleJson)
    local isJobVehicle = jobName == 'ambulance' or jobName == 'police' or jobName == 'council'
    local job = isJobVehicle and tostring(jobName) or ''

    local attempts = {
        {
            sql = 'INSERT INTO owned_vehicles (owner, plate, vehicle, type, job, stored, vehiclename, health_vehicles) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE owner = VALUES(owner), vehicle = VALUES(vehicle), type = VALUES(type), job = VALUES(job), stored = VALUES(stored), vehiclename = VALUES(vehiclename), health_vehicles = VALUES(health_vehicles)',
            params = { identifier, plate, vehicleJson, vehicleType, job, 0, vehicleName, healthVehicleJson }
        },
        {
            sql = 'INSERT INTO owned_vehicles (owner, plate, vehicle, type, stored, vehiclename, health_vehicles) VALUES (?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE owner = VALUES(owner), vehicle = VALUES(vehicle), type = VALUES(type), stored = VALUES(stored), vehiclename = VALUES(vehiclename), health_vehicles = VALUES(health_vehicles)',
            params = { identifier, plate, vehicleJson, vehicleType, 0, vehicleName, healthVehicleJson }
        },
        {
            sql = 'INSERT INTO owned_vehicles (owner, plate, vehicle, type, job, stored, vehiclename) VALUES (?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE owner = VALUES(owner), vehicle = VALUES(vehicle), type = VALUES(type), job = VALUES(job), stored = VALUES(stored), vehiclename = VALUES(vehiclename)',
            params = { identifier, plate, vehicleJson, vehicleType, job, 0, vehicleName }
        },
        {
            sql = 'INSERT INTO owned_vehicles (owner, plate, vehicle, type, stored, vehiclename) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE owner = VALUES(owner), vehicle = VALUES(vehicle), type = VALUES(type), stored = VALUES(stored), vehiclename = VALUES(vehiclename)',
            params = { identifier, plate, vehicleJson, vehicleType, 0, vehicleName }
        },
        {
            sql = 'INSERT INTO owned_vehicles (owner, plate, vehicle, type, job, vehiclename) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE owner = VALUES(owner), vehicle = VALUES(vehicle), type = VALUES(type), job = VALUES(job), vehiclename = VALUES(vehiclename)',
            params = { identifier, plate, vehicleJson, vehicleType, job, vehicleName }
        },
        {
            sql = 'INSERT INTO owned_vehicles (owner, plate, vehicle, vehiclename) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE owner = VALUES(owner), vehicle = VALUES(vehicle), vehiclename = VALUES(vehiclename)',
            params = { identifier, plate, vehicleJson, vehicleName }
        },
        {
            sql = 'INSERT INTO owned_vehicles (owner, plate, vehicle, type, job, stored) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE owner = VALUES(owner), vehicle = VALUES(vehicle), type = VALUES(type), job = VALUES(job), stored = VALUES(stored)',
            params = { identifier, plate, vehicleJson, vehicleType, job, 0 }
        },
        {
            sql = 'INSERT INTO owned_vehicles (owner, plate, vehicle, type, stored) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE owner = VALUES(owner), vehicle = VALUES(vehicle), type = VALUES(type), stored = VALUES(stored)',
            params = { identifier, plate, vehicleJson, vehicleType, 0 }
        },
        {
            sql = 'INSERT INTO owned_vehicles (owner, plate, vehicle, type, job) VALUES (?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE owner = VALUES(owner), vehicle = VALUES(vehicle), type = VALUES(type), job = VALUES(job)',
            params = { identifier, plate, vehicleJson, vehicleType, job }
        },
        {
            sql = 'INSERT INTO owned_vehicles (owner, plate, vehicle) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE owner = VALUES(owner), vehicle = VALUES(vehicle)',
            params = { identifier, plate, vehicleJson }
        }
    }

    local startIndex = math.max(1, math.min(#attempts, upsertAttemptIndex or 1))

    for offset = 0, (#attempts - 1) do
        local i = ((startIndex + offset - 1) % #attempts) + 1
        local ok = pcall(function()
            MySQL.insert.await(attempts[i].sql, attempts[i].params)
        end)
        if ok then
            upsertAttemptIndex = i
            return true
        end
    end

    return false
end

local function buildGarageVehiclePayload(cfg, vehicleProps, plate, vehicleJson)
    local jobName = tostring(cfg.category or '')
    local isJobVehicle = jobName == 'ambulance' or jobName == 'police' or jobName == 'council'

    return {
        plate = tostring(plate),
        stored = false,
        police = 0,
        job = isJobVehicle and jobName or '',
        type = tostring(vehicleProps.type or cfg.typecar or 'car'),
        vehiclename = tostring(cfg.name or cfg.model or ''),
        health_vehicles = json.encode({
            engine = 1000.0,
            fuel = tonumber(vehicleProps.fuelLevel) or 100.0,
            health_body = 1000.0,
            tyres = {},
            doors = {}
        }),
        vehicle = vehicleJson
    }
end

local function syncVehicleToGarage(src, cfg, vehicleProps, plate, vehicleJson)
    if GetResourceState('APEX-Garage') ~= 'started' then return end

    local payload = buildGarageVehiclePayload(cfg, vehicleProps, plate, vehicleJson)

    local ok = pcall(function()
        exports['APEX-Garage']:SyncOwnedVehicle(src, payload)
    end)

    if not ok then
        TriggerClientEvent(Val .. ':Garage:SyncOwnedVehicle', src, payload)
    end
end

local function isPlateOwnedByAnother(identifier, plate)
    local owner = getPlateOwnerCached(compactPlate(plate))
    if not owner or owner == '' then
        return false
    end
    return owner ~= tostring(identifier)
end

local function saveOwnedVehicle(src, vehicleProps, purchaseModel)
    fetchESX()
    pruneStateTables(false)
    local xPlayer = getPlayerCached(src)
    if not xPlayer then return false end
    if type(vehicleProps) ~= 'table' then return false end

    if isOnCooldown(saveOwnedCooldowns, src, OWNED_SAVE_COOLDOWN_MS) then
        return false
    end

    local identifier = xPlayer.getIdentifier and xPlayer.getIdentifier() or xPlayer.identifier
    if not identifier or identifier == '' then return false end

    local ticket = purchaseTickets[src]
    if not ticket then return false end

    local now = GetGameTimer()
    if now > (tonumber(ticket.expiresAt) or 0) then
        purchaseTickets[src] = nil
        return false
    end

    local model = tostring(purchaseModel or '')
    if model == '' then return false end
    if model ~= tostring(ticket.model) then return false end

    local cfg = vehCfg(model)
    if not cfg then return false end

    local ticketShopIndex = tonumber(ticket.shopIndex)
    if ticketShopIndex then
        local currentShopIndex = findShopInRange(src, SHOP_SAVE_MAX_DISTANCE)
        if currentShopIndex ~= ticketShopIndex then return false end
    elseif not isPlayerNearAnyShop(src, SHOP_SAVE_MAX_DISTANCE) then
        return false
    end

    local plate = normalizePlate(vehicleProps.plate)
    if plate == '' then return false end
    if isPlateOwnedByAnother(identifier, plate) then return false end

    local expectedModelHash = GetHashKey(cfg.model)
    if type(vehicleProps.model) == 'number' and vehicleProps.model ~= expectedModelHash then
        return false
    end

    vehicleProps.plate = plate
    vehicleProps.model = expectedModelHash

    local resolvedVehicleName = tostring(cfg.name or cfg.model or '')
    local vehicleJson = json.encode(vehicleProps)
    local vehicleType = tostring(vehicleProps.type or 'car')
    local jobName = cfg.category
    local healthVehicleJson = json.encode({
        engine = tonumber(vehicleProps.engineHealth) or 1000.0,
        fuel = tonumber(vehicleProps.fuelLevel) or 100.0,
        health_body = tonumber(vehicleProps.bodyHealth) or 1000.0,
        tyres = {},
        doors = {}
    })

    local saved = upsertOwnedVehicle(identifier, plate, vehicleJson, vehicleType, jobName, resolvedVehicleName, healthVehicleJson)
    if not saved then return false end

    plateTakenCache[compactPlate(plate)] = {
        owner = tostring(identifier),
        expiresAt = GetGameTimer() + PLATE_CACHE_TTL_MS
    }

    purchaseTickets[src] = nil
    webhookTickets[src] = {
        model = tostring(cfg.model),
        plate = plate,
        expiresAt = now + WEBHOOK_TICKET_TTL_MS
    }

    local pending = pendingWebhookRequests[src]
    if pending then
        local pendingModel = tostring(pending.model or '')
        local pendingPlate = normalizePlate(pending.plate)
        if pendingModel == tostring(cfg.model) and pendingPlate == plate then
            webhookTickets[src] = nil
            pendingWebhookRequests[src] = nil
            sendPurchaseWebhook(src, tostring(cfg.model), plate)
        end
    end

    syncVehicleToGarage(src, cfg, vehicleProps, plate, vehicleJson)

    return true
end

RegisterNetEvent(CALLBACK_NAMESPACE .. ':setVehicleOwned')
AddEventHandler(CALLBACK_NAMESPACE .. ':setVehicleOwned', function(vehicleProps, jobName, vehicleName, purchaseModel)
    saveOwnedVehicle(source, vehicleProps, purchaseModel)
end)

if Val ~= CALLBACK_NAMESPACE then
    RegisterNetEvent(Val .. ':setVehicleOwned')
    AddEventHandler(Val .. ':setVehicleOwned', function(vehicleProps, jobName, vehicleName, purchaseModel)
        saveOwnedVehicle(source, vehicleProps, purchaseModel)
    end)
end


local function getSteamIdentifier(xPlayer)
    if PlayerModule.getSteamIdentifier then
        return PlayerModule.getSteamIdentifier(xPlayer)
    end
    return 'N/A'
end

local function getDiscordIdentifier(xPlayer)
    if PlayerModule.getDiscordIdentifier then
        return PlayerModule.getDiscordIdentifier(xPlayer)
    end
    return 'N/A'
end

local function getDiscordUserId(discordIdentifier)
    if PlayerModule.getDiscordUserId then
        return PlayerModule.getDiscordUserId(discordIdentifier)
    end
    return 'N/A'
end

local function resolveWebhookUrl()
    local fromConvar = tostring(GetConvar('val_vehicleshop_webhook_buy', '') or '')
    if fromConvar ~= '' then
        return fromConvar
    end

    local strictConvarOnly = not not (Config and Config.Security and Config.Security.StrictWebhookConvarOnly)
    if strictConvarOnly then
        return ''
    end

    if Config["DiscordWebhook"] and Config["DiscordWebhook"].BuyVehicle then
        return tostring(Config["DiscordWebhook"].BuyVehicle)
    end

    return ''
end

local function webhookQueueSize()
    return webhookQueueTail - webhookQueueHead + 1
end

local function snapshotWebhookQueue()
    local out = {}
    for i = webhookQueueHead, webhookQueueTail do
        local item = webhookQueue[i]
        if item then
            out[#out + 1] = item
        end
    end
    return out
end

local function persistWebhookQueue()
    local payload = json.encode(snapshotWebhookQueue())
    if payload then
        SaveResourceFile(Val, 'webhook_queue.json', payload, -1)
    end
end

local function scheduleWebhookPersist()
    if webhookPersistScheduled then return end
    webhookPersistScheduled = true

    SetTimeout(1500, function()
        webhookPersistScheduled = false
        if webhookQueueDirty then
            persistWebhookQueue()
            webhookQueueDirty = false
        end
    end)
end

local function enqueueWebhookRequest(item)
    if type(item) ~= 'table' then return end

    webhookQueueTail = webhookQueueTail + 1
    webhookQueue[webhookQueueTail] = item
    webhookQueueDirty = true
    scheduleWebhookPersist()

    local qSize = webhookQueueSize()
    if qSize >= WEBHOOK_QUEUE_WARN_SIZE and qSize % 50 == 0 then
        print(('[%s] webhook queue backlog=%d'):format(Val, qSize))
    end
end

local function parseRetryAfterMs(headers)
    if type(headers) ~= 'table' then return nil end

    for key, value in pairs(headers) do
        if tostring(key):lower() == 'retry-after' then
            local retrySeconds = tonumber(value)
            if retrySeconds and retrySeconds > 0 then
                return math.floor(retrySeconds * 1000)
            end
        end
    end

    return nil
end

local function nextRetryDelayMs(attempt, retryAfterMs)
    if retryAfterMs and retryAfterMs > 0 then
        return math.max(retryAfterMs, WEBHOOK_RETRY_BASE_MS)
    end

    local exp = WEBHOOK_RETRY_BASE_MS * math.max(1, 2 ^ math.max(0, (attempt or 1) - 1))
    return math.min(exp, WEBHOOK_RETRY_MAX_MS)
end

local function loadPersistedWebhookQueue()
    local raw = LoadResourceFile(Val, 'webhook_queue.json')
    if not raw or raw == '' then return end

    local ok, rows = pcall(json.decode, raw)
    if not ok or type(rows) ~= 'table' then
        return
    end

    local now = GetGameTimer()
    for i = 1, #rows do
        local item = rows[i]
        if type(item) == 'table' and type(item.url) == 'string' and item.url ~= '' and type(item.body) == 'table' then
            item.attempt = tonumber(item.attempt) or 0
            item.nextAttemptAt = tonumber(item.nextAttemptAt) or now
            enqueueWebhookRequest(item)
        end
    end

    if #rows > 0 then
        print(('[%s] restored %d webhook item(s) from disk'):format(Val, #rows))
    end
end

sendPurchaseWebhook = function(src, carKey, plate)
    local url = resolveWebhookUrl()
    if url == '' then return end

    fetchESX()
    local xPlayer = getPlayerCached(src)
    if not xPlayer then return end

    local cfg = vehCfg(carKey) or {}
    local carName = cfg.name or cfg.model or tostring(carKey)
    local model = cfg.model or tostring(carKey)
    local price = ESX.Math.GroupDigits(tonumber(cfg.price) or 0)
    local steamId = getSteamIdentifier(xPlayer)
    local discordIdentifier = getDiscordIdentifier(xPlayer)
    local discordUserId = getDiscordUserId(discordIdentifier)
    local discordName = GetPlayerName(src) or ('ID '..src)
    local playerName = xPlayer.getName and xPlayer.getName() or discordName

    local embed = UiModule.buildPurchaseEmbed and UiModule.buildPurchaseEmbed({
        playerName = playerName,
        discordName = discordName,
        discordIdentifier = (discordUserId ~= 'N/A' and discordUserId or discordIdentifier),
        steamId = steamId,
        carName = carName,
        model = model,
        plate = tostring(plate or 'N/A'),
        price = tostring(price)
    }) or {}

    local body = {
        username = "VAL Legacy [LOG]",
        embeds = embed
    }

    enqueueWebhookRequest({
        url = url,
        body = body,
        attempt = 0,
        nextAttemptAt = GetGameTimer(),
        createdAt = GetGameTimer()
    })
end

CreateThread(function()
    loadPersistedWebhookQueue()

    while true do
        Wait(WEBHOOK_WORKER_TICK_MS)

        if webhookQueueInFlight then
            goto continue
        end

        local item = webhookQueue[webhookQueueHead]
        if not item then
            goto continue
        end

        local now = GetGameTimer()
        if now < (tonumber(item.nextAttemptAt) or 0) then
            goto continue
        end

        webhookQueueInFlight = true

        PerformHttpRequest(item.url, function(statusCode, _responseBody, headers)
            local status = tonumber(statusCode) or 0

            if status >= 200 and status < 300 then
                webhookQueue[webhookQueueHead] = nil
                webhookQueueHead = webhookQueueHead + 1
                if webhookQueueHead > webhookQueueTail then
                    webhookQueueHead = 1
                    webhookQueueTail = 0
                    webhookQueue = {}
                end
                webhookQueueDirty = true
                scheduleWebhookPersist()
            else
                item.attempt = (tonumber(item.attempt) or 0) + 1
                local retryAfterMs = parseRetryAfterMs(headers)
                local delayMs = nextRetryDelayMs(item.attempt, retryAfterMs)
                item.nextAttemptAt = GetGameTimer() + delayMs
                webhookQueueDirty = true
                scheduleWebhookPersist()

                if item.attempt == 1 or item.attempt % 5 == 0 then
                    print(('[%s] webhook send failed status=%s retry_in=%dms attempt=%d queue=%d'):format(
                        Val,
                        tostring(status),
                        delayMs,
                        item.attempt,
                        webhookQueueSize()
                    ))
                end
            end

            webhookQueueInFlight = false
        end, 'POST', json.encode(item.body), { ['Content-Type'] = 'application/json' })

        ::continue::
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= Val then return end
    persistWebhookQueue()
end)

RegisterNetEvent(Val .. ':logVehiclePurchase')
AddEventHandler(Val .. ':logVehiclePurchase', function(carKey, plate)
    local src = source
    pruneStateTables(false)
    local ticket = webhookTickets[src]

    local now = GetGameTimer()
    if not ticket then
        pendingWebhookRequests[src] = {
            model = tostring(carKey or ''),
            plate = normalizePlate(plate),
            expiresAt = now + WEBHOOK_TICKET_TTL_MS
        }
        return
    end

    if now > (tonumber(ticket.expiresAt) or 0) then
        webhookTickets[src] = nil
        return
    end

    local cfg = vehCfg(carKey)
    local requestedModel = cfg and tostring(cfg.model) or tostring(carKey or '')
    local requestedPlate = normalizePlate(plate)

    if requestedModel ~= tostring(ticket.model) or requestedPlate ~= tostring(ticket.plate) then
        return
    end

    webhookTickets[src] = nil
    sendPurchaseWebhook(src, requestedModel, requestedPlate)
end)
