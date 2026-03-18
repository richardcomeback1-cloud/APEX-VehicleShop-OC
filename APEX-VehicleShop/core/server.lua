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

-- Runtime architecture optimized for large server populations.
local Runtime = {
    PLAYER_CACHE = {},
    PLAYER_PEDS = {},
    PLAYER_STATE = {},
    JOB_INDEX = {},
    LOCK_SYSTEM = {},
    WRITE_QUEUE = {
        ownedVehicles = {},
        head = 1,
        tail = 0
    },
    TASK_SCHEDULER = {},
    WEBHOOK_QUEUE = {
        data = {},
        head = 1,
        tail = 0,
        inFlight = false,
        dirty = false,
        persistScheduled = false
    }
}

local purchaseTickets = {}
local webhookTickets = {}
local pendingWebhookRequests = {}
local plateTakenCache = {}

local PURCHASE_TICKET_TTL_MS = 60 * 1000
local WEBHOOK_TICKET_TTL_MS = 60 * 1000
local TESTDRIVE_COOLDOWN_MS = 5000
local SHOP_INTERACTION_MAX_DISTANCE = tonumber((Config and Config.Security and Config.Security.ShopInteractDistance) or 15.0) or 15.0
local SHOP_SAVE_MAX_DISTANCE = tonumber((Config and Config.Security and Config.Security.ShopSaveDistance) or 40.0) or 40.0
local PLATE_CACHE_TTL_MS = tonumber((Config and Config.Security and Config.Security.PlateCacheTtlMs) or 10000) or 10000
local BUY_COOLDOWN_MS = tonumber((Config and Config.Security and Config.Security.BuyCooldownMs) or 1200) or 1200
local OWNED_SAVE_COOLDOWN_MS = tonumber((Config and Config.Security and Config.Security.SaveOwnedCooldownMs) or 1500) or 1500
local WRITE_QUEUE_BATCH_SIZE = tonumber((Config and Config.Security and Config.Security.WriteQueueBatchSize) or 50) or 50
local WRITE_QUEUE_ACTIVE_TICK_MS = tonumber((Config and Config.Security and Config.Security.WriteQueueActiveTickMs) or 1000) or 1000
local WRITE_QUEUE_IDLE_TICK_MS = tonumber((Config and Config.Security and Config.Security.WriteQueueIdleTickMs) or 10000) or 10000
local WRITE_QUEUE_WARN_SIZE = tonumber((Config and Config.Security and Config.Security.WriteQueueWarnSize) or 100) or 100
local WEBHOOK_WORKER_TICK_MS = tonumber((Config and Config.Security and Config.Security.WebhookWorkerTickMs) or 250) or 250
local WEBHOOK_IDLE_TICK_MS = tonumber((Config and Config.Security and Config.Security.WebhookIdleTickMs) or math.max(1000, WEBHOOK_WORKER_TICK_MS * 4)) or math.max(1000, WEBHOOK_WORKER_TICK_MS * 4)
local WEBHOOK_RETRY_BASE_MS = tonumber((Config and Config.Security and Config.Security.WebhookRetryBaseMs) or 2000) or 2000
local WEBHOOK_RETRY_MAX_MS = tonumber((Config and Config.Security and Config.Security.WebhookRetryMaxMs) or 60000) or 60000
local WEBHOOK_QUEUE_WARN_SIZE = tonumber((Config and Config.Security and Config.Security.WebhookQueueWarnSize) or 200) or 200
local PLAYER_CACHE_TTL_MS = tonumber((Config and Config.Security and Config.Security.PlayerCacheTtlMs) or 1000) or 1000

local lastPruneAt = 0


VehicleShopModules = VehicleShopModules or {}
VehicleShopModules.Player = VehicleShopModules.Player or {}
VehicleShopModules.Inventory = VehicleShopModules.Inventory or {}
VehicleShopModules.Economy = VehicleShopModules.Economy or {}
VehicleShopModules.Jobs = VehicleShopModules.Jobs or {}
VehicleShopModules.UI = VehicleShopModules.UI or {}

local restrictedJobs = {
    ambulance = true,
    police = true,
    council = true
}

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

function VehicleShopModules.Inventory.countItem(xPlayer, itemName)
    if not xPlayer or not xPlayer.getInventoryItem then
        return 0
    end

    local item = xPlayer.getInventoryItem(itemName)
    if item and item.count then
        return tonumber(item.count) or 0
    end

    return 0
end

function VehicleShopModules.Jobs.isRestricted(category)
    return restrictedJobs[tostring(category)] == true
end

function VehicleShopModules.Jobs.canViewVehicle(xPlayer, cfg)
    if not cfg then
        return false
    end

    local category = tostring(cfg.category or '')
    if not VehicleShopModules.Jobs.isRestricted(category) then
        return true
    end

    if not xPlayer or not xPlayer.job then
        return false
    end

    return xPlayer.job.name == category
end

function VehicleShopModules.Jobs.canAccessVehicle(xPlayer, cfg)
    if not VehicleShopModules.Jobs.canViewVehicle(xPlayer, cfg) then
        return false
    end

    local grade = tonumber(cfg and cfg.grade or 0) or 0
    return (xPlayer.job.grade or 0) >= grade
end

local cache = {}

function VehicleShopModules.Player.getCached(esx, src, ttlMs)
    local now = GetGameTimer()
    local cached = cache[src]
    if cached and cached.expiresAt > now and cached.value then
        return cached.value
    end

    local xPlayer = esx.GetPlayerFromId(src)
    cache[src] = {
        value = xPlayer,
        expiresAt = now + (tonumber(ttlMs) or 1000)
    }

    return xPlayer
end

function VehicleShopModules.Player.invalidate(src)
    cache[src] = nil
end

function VehicleShopModules.Player.prune()
    local now = GetGameTimer()
    for src, entry in pairs(cache) do
        if (not entry) or now > (tonumber(entry.expiresAt) or 0) then
            cache[src] = nil
        end
    end
end

function VehicleShopModules.Player.getSteamIdentifier(xPlayer)
    local ids = xPlayer.getIdentifiers and xPlayer.getIdentifiers() or GetPlayerIdentifiers(xPlayer.source)
    if ids then
        for _, id in pairs(ids) do
            if type(id) == 'string' and id:sub(1, 6) == 'steam:' then
                return id
            end
        end
    end
    return 'N/A'
end

function VehicleShopModules.Player.getDiscordIdentifier(xPlayer)
    local ids = xPlayer.getIdentifiers and xPlayer.getIdentifiers() or GetPlayerIdentifiers(xPlayer.source)
    if ids then
        for _, id in pairs(ids) do
            if type(id) == 'string' and id:sub(1, 8) == 'discord:' then
                return id
            end
        end
    end
    return 'N/A'
end

function VehicleShopModules.Player.getDiscordUserId(discordIdentifier)
    local raw = tostring(discordIdentifier or '')
    local discordId = raw:match('^discord:(%d+)$')
    return discordId or 'N/A'
end

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

local vehicleConfigIndex = nil
local shopPointIndex = nil
local upsertAttemptIndex = 1

local Modules = VehicleShopModules or {}
local PlayerModule = Modules.Player or {}
local EconomyModule = Modules.Economy or {}
local JobsModule = Modules.Jobs or {}
local UiModule = Modules.UI or {}

local sendPurchaseWebhook
local getPlayerPedCached

local function compactPlate(plate)
    local trimmed = tostring(plate or ''):gsub('^%s*(.-)%s*$', '%1'):upper()
    return trimmed:gsub('%s+', '')
end

local function normalizePlate(plate)
    return tostring(plate or ''):gsub('^%s*(.-)%s*$', '%1'):upper()
end

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

local function buildShopPointIndex()
    if shopPointIndex then return shopPointIndex end

    shopPointIndex = {}
    for shopIndex, shop in pairs(Config['ZONE_SHOP'] or {}) do
        local points = collectShopPoints(shop)
        if #points > 0 then
            shopPointIndex[#shopPointIndex + 1] = {
                shopIndex = shopIndex,
                points = points
            }
        end
    end

    return shopPointIndex
end

local function sqrDistance(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    local dz = a.z - b.z
    return (dx * dx) + (dy * dy) + (dz * dz)
end

local function findShopInRange(src, maxDistance)
    local ped = getPlayerPedCached(src)
    if not ped or ped == 0 then return nil end

    local coords = GetEntityCoords(ped)
    if not coords then return nil end

    local allowedDistance = tonumber(maxDistance) or SHOP_INTERACTION_MAX_DISTANCE
    local maxDistSqr = allowedDistance * allowedDistance
    local nearestShopIndex = nil
    local nearestDistanceSqr = nil
    local shops = buildShopPointIndex()

    for i = 1, #shops do
        local shop = shops[i]
        local points = shop.points
        for pointIndex = 1, #points do
            local distSqr = sqrDistance(coords, points[pointIndex])
            if distSqr <= maxDistSqr and (not nearestDistanceSqr or distSqr < nearestDistanceSqr) then
                nearestDistanceSqr = distSqr
                nearestShopIndex = shop.shopIndex
            end
        end
    end

    return nearestShopIndex
end

local function appendVehicleConfigIndex(target, source)
    if type(source) ~= 'table' then
        return
    end

    for key, cfg in pairs(source) do
        target[tostring(key)] = cfg
        if cfg and cfg.model then
            target[tostring(cfg.model)] = cfg
        end
    end
end

local function buildVehicleConfigIndex()
    if vehicleConfigIndex then return vehicleConfigIndex end

    vehicleConfigIndex = {}
    appendVehicleConfigIndex(vehicleConfigIndex, Config['vehicles'])
    appendVehicleConfigIndex(vehicleConfigIndex, Config['JobVehicles'])

    return vehicleConfigIndex
end

local function vehCfg(model)
    return buildVehicleConfigIndex()[tostring(model)]
end


local function normalizeJobName(jobName)
    if jobName == nil then
        return ''
    end

    return tostring(jobName)
end

local function shopAllowsJob(shopConfig, xPlayer)
    if type(shopConfig) ~= 'table' then
        return false
    end

    local visibleJobs = shopConfig.visibleJobs
    if visibleJobs == nil then
        return true
    end

    local playerJob = normalizeJobName(xPlayer and xPlayer.job and xPlayer.job.name)
    if playerJob == '' then
        return false
    end

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

local function getShopVehiclePool(shopConfig)
    local sourceType = tostring(shopConfig and shopConfig.vehicleSource or 'public')
    local pool = {}

    local function append(source)
        if type(source) ~= 'table' then
            return
        end

        for key, cfg in pairs(source) do
            pool[tostring(key)] = cfg
            if cfg and cfg.model then
                pool[tostring(cfg.model)] = cfg
            end
        end
    end

    if sourceType == 'job' then
        append(Config['JobVehicles'])
    elseif sourceType == 'all' then
        append(Config['vehicles'])
        append(Config['JobVehicles'])
    else
        append(Config['vehicles'])
    end

    return pool
end

local function shopHasVehicle(shopConfig, model)
    if type(shopConfig) ~= 'table' then
        return false
    end

    local vehiclePool = getShopVehiclePool(shopConfig)
    local configuredList = shopConfig.vehicleList
    if configuredList == nil then
        return vehiclePool[tostring(model or '')] ~= nil
    end

    local modelName = tostring(model or '')
    if modelName == '' or type(configuredList) ~= 'table' then
        return false
    end

    for i = 1, #configuredList do
        local vehicleKey = tostring(configuredList[i])
        local cfg = vehiclePool[vehicleKey]
        if cfg and tostring(cfg.model or vehicleKey) == modelName then
            return true
        end
    end

    return false
end
local function lockAcquire(key)
    if Runtime.LOCK_SYSTEM[key] then return false end
    Runtime.LOCK_SYSTEM[key] = true
    return true
end

local function lockRelease(key)
    Runtime.LOCK_SYSTEM[key] = nil
end

local function isOnCooldown(state, cooldownKey, cooldownMs)
    local now = GetGameTimer()
    state.cooldowns = state.cooldowns or {}
    local readyAt = tonumber(state.cooldowns[cooldownKey] or 0) or 0
    if now < readyAt then
        return true
    end

    state.cooldowns[cooldownKey] = now + (tonumber(cooldownMs) or 0)
    return false
end

local function getPlayerState(src)
    local state = Runtime.PLAYER_STATE[src]
    if state then return state end

    state = {
        cooldowns = {},
        flags = {},
        activeTestBucket = nil,
        webhooks = {}
    }
    Runtime.PLAYER_STATE[src] = state
    return state
end

local function jobIndexRemove(src, jobName)
    if not jobName or jobName == '' then return end
    local bucket = Runtime.JOB_INDEX[jobName]
    if not bucket then return end
    bucket[src] = nil
    if next(bucket) == nil then
        Runtime.JOB_INDEX[jobName] = nil
    end
end

local function jobIndexSet(src, newJob)
    local state = getPlayerState(src)
    local oldJob = state.flags.jobName
    if oldJob then
        jobIndexRemove(src, oldJob)
    end

    if newJob and newJob ~= '' then
        Runtime.JOB_INDEX[newJob] = Runtime.JOB_INDEX[newJob] or {}
        Runtime.JOB_INDEX[newJob][src] = true
    end

    state.flags.jobName = newJob
end

local function getPlayerCached(src)
    fetchESX()

    local now = GetGameTimer()
    local cached = Runtime.PLAYER_CACHE[src]
    if cached and cached.expiresAt > now and cached.value then
        return cached.value
    end

    local xPlayer
    if PlayerModule.getCached then
        xPlayer = PlayerModule.getCached(ESX, src, PLAYER_CACHE_TTL_MS)
    else
        xPlayer = ESX.GetPlayerFromId(src)
    end

    Runtime.PLAYER_CACHE[src] = {
        value = xPlayer,
        expiresAt = now + PLAYER_CACHE_TTL_MS
    }

    if xPlayer and xPlayer.job and xPlayer.job.name then
        jobIndexSet(src, xPlayer.job.name)
    end

    return xPlayer
end

local function invalidatePlayerCache(src)
    if PlayerModule.invalidate then
        PlayerModule.invalidate(src)
    end
    Runtime.PLAYER_CACHE[src] = nil
    Runtime.PLAYER_PEDS[src] = nil
end

getPlayerPedCached = function(src)
    local now = GetGameTimer()
    local cached = Runtime.PLAYER_PEDS[src]
    if cached and cached.expiresAt > now and cached.value and cached.value ~= 0 then
        return cached.value
    end

    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return 0 end

    Runtime.PLAYER_PEDS[src] = {
        value = ped,
        expiresAt = now + 1000
    }

    return ped
end

local function validateSource(src)
    return type(src) == 'number' and src > 0 and GetPlayerName(src) ~= nil
end

local function validateEventContext(src, opts)
    if not validateSource(src) then return false, nil end

    local state = getPlayerState(src)
    local matchedShopIndex = nil

    if opts and opts.rateKey and opts.rateMs then
        if isOnCooldown(state, opts.rateKey, opts.rateMs) then
            return false, nil
        end
    end

    if opts and opts.requireShopDistance then
        matchedShopIndex = findShopInRange(src, tonumber(opts.requireShopDistance))
        if not matchedShopIndex then
            return false, nil
        end
    end

    if opts and opts.requirePlayer then
        local xPlayer = getPlayerCached(src)
        if not xPlayer then
            return false, matchedShopIndex
        end

        if opts.requireJob then
            local job = xPlayer.job and xPlayer.job.name or ''
            if job ~= opts.requireJob then
                return false, matchedShopIndex
            end
        end
    end

    return true, matchedShopIndex
end

local function getPlateOwnerCached(compact)
    local now = GetGameTimer()
    local cached = plateTakenCache[compact]
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

local function leaveTestBucket(src)
    local state = getPlayerState(src)
    local active = state.activeTestBucket
    if not active then return end

    local targetBucket = tonumber(active.previousBucket) or 0
    pcall(function()
        SetPlayerRoutingBucket(src, targetBucket)
    end)

    state.activeTestBucket = nil
end

local function enterTestBucket(src)
    local state = getPlayerState(src)
    local currentBucket = 0

    pcall(function()
        currentBucket = GetPlayerRoutingBucket(src)
    end)

    local isolatedBucket = 50000 + src
    state.activeTestBucket = {
        previousBucket = tonumber(currentBucket) or 0,
        currentBucket = isolatedBucket
    }

    SetPlayerRoutingBucket(src, isolatedBucket)
end

local function clearPlayerState(src)
    leaveTestBucket(src)
    purchaseTickets[src] = nil
    webhookTickets[src] = nil
    pendingWebhookRequests[src] = nil
    jobIndexRemove(src, getPlayerState(src).flags.jobName)
    Runtime.PLAYER_STATE[src] = nil
    invalidatePlayerCache(src)
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

local function queueOwnedVehicleWrite(payload)
    Runtime.WRITE_QUEUE.tail = Runtime.WRITE_QUEUE.tail + 1
    Runtime.WRITE_QUEUE.ownedVehicles[Runtime.WRITE_QUEUE.tail] = payload

    local qSize = Runtime.WRITE_QUEUE.tail - Runtime.WRITE_QUEUE.head + 1
    if qSize >= WRITE_QUEUE_WARN_SIZE and qSize % 25 == 0 then
        print(('[%s] owned vehicle write queue backlog=%d'):format(Val, qSize))
    end
end

local function popOwnedVehicleWrite()
    local item = Runtime.WRITE_QUEUE.ownedVehicles[Runtime.WRITE_QUEUE.head]
    if not item then return nil end

    Runtime.WRITE_QUEUE.ownedVehicles[Runtime.WRITE_QUEUE.head] = nil
    Runtime.WRITE_QUEUE.head = Runtime.WRITE_QUEUE.head + 1

    if Runtime.WRITE_QUEUE.head > Runtime.WRITE_QUEUE.tail then
        Runtime.WRITE_QUEUE.head = 1
        Runtime.WRITE_QUEUE.tail = 0
        Runtime.WRITE_QUEUE.ownedVehicles = {}
    end

    return item
end

local function writeQueueSize()
    return Runtime.WRITE_QUEUE.tail - Runtime.WRITE_QUEUE.head + 1
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

local function flushWriteQueue()
    local backlog = writeQueueSize()
    if backlog <= 0 then
        return WRITE_QUEUE_IDLE_TICK_MS
    end

    local batchSize = math.max(1, WRITE_QUEUE_BATCH_SIZE)
    if backlog >= (WRITE_QUEUE_BATCH_SIZE * 8) then
        batchSize = math.max(batchSize, WRITE_QUEUE_BATCH_SIZE * 4)
    elseif backlog >= (WRITE_QUEUE_BATCH_SIZE * 4) then
        batchSize = math.max(batchSize, WRITE_QUEUE_BATCH_SIZE * 2)
    end

    local processed = 0
    while processed < batchSize do
        local item = popOwnedVehicleWrite()
        if not item then
            break
        end

        local ok = upsertOwnedVehicle(item.identifier, item.plate, item.vehicleJson, item.vehicleType, item.jobName, item.vehicleName, item.healthVehicleJson)
        if not ok then
            -- Retry by pushing back to queue tail to avoid data loss under transient DB issues.
            queueOwnedVehicleWrite(item)
            break
        end

        processed = processed + 1
    end

    if writeQueueSize() > 0 then
        return math.max(250, WRITE_QUEUE_ACTIVE_TICK_MS)
    end

    return WRITE_QUEUE_IDLE_TICK_MS
end

local function isPlateOwnedByAnother(identifier, plate)
    local owner = getPlateOwnerCached(compactPlate(plate))
    if not owner or owner == '' then
        return false
    end
    return owner ~= tostring(identifier)
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

local function pruneStateTables(force)
    local now = GetGameTimer()
    if not force and (now - lastPruneAt) < 2500 then
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

    for src, pending in pairs(pendingWebhookRequests) do
        if now > (tonumber(pending.expiresAt) or 0) then
            pendingWebhookRequests[src] = nil
        end
    end

    for compact, data in pairs(plateTakenCache) do
        if (not data) or now > (tonumber(data.expiresAt) or 0) then
            plateTakenCache[compact] = nil
        end
    end

    if PlayerModule.prune then
        PlayerModule.prune()
    end

    for src, cached in pairs(Runtime.PLAYER_CACHE) do
        if (not cached) or now > (tonumber(cached.expiresAt) or 0) then
            Runtime.PLAYER_CACHE[src] = nil
        end
    end

    for src, cached in pairs(Runtime.PLAYER_PEDS) do
        if (not cached) or now > (tonumber(cached.expiresAt) or 0) then
            Runtime.PLAYER_PEDS[src] = nil
        end
    end
end

local function cbIsPlateTaken(source, cb, plate)
    if not validateSource(source) then cb(false) return end
    if type(plate) ~= 'string' then cb(false) return end

    pruneStateTables(false)

    local compact = compactPlate(plate)
    if compact == '' then
        cb(false)
        return
    end

    local owner = getPlateOwnerCached(compact)
    cb(owner ~= nil and owner ~= '')
end

local function cbBuyVehicle(source, cb, model, _price, payment)
    local isValid, shopIndex = validateEventContext(source, {
        rateKey = 'buy_callback',
        rateMs = BUY_COOLDOWN_MS,
        requirePlayer = true,
        requireShopDistance = SHOP_INTERACTION_MAX_DISTANCE
    })
    if not isValid then
        cb(false)
        return
    end

    if type(model) ~= 'string' or model == '' then cb(false) return end
    if type(payment) ~= 'string' then cb(false) return end

    pruneStateTables(false)

    local xPlayer = getPlayerCached(source)
    if not xPlayer then cb(false) return end

    local cfg = vehCfg(model)
    if not cfg or not cfg.model then cb(false) return end

    local shopConfig = Config['ZONE_SHOP'] and Config['ZONE_SHOP'][shopIndex]
    if not shopAllowsJob(shopConfig, xPlayer) or not shopHasVehicle(shopConfig, cfg.model) then
        cb(false)
        return
    end

    if JobsModule.canAccessVehicle and (not JobsModule.canAccessVehicle(xPlayer, cfg)) then
        cb(false)
        return
    end

    local amount = tonumber(cfg.price or 0) or 0
    if amount <= 0 or not canAfford(xPlayer, payment, amount) then
        cb(false)
        return
    end

    removeMoney(xPlayer, payment, amount)

    purchaseTickets[source] = {
        model = tostring(cfg.model),
        shopIndex = shopIndex,
        expiresAt = GetGameTimer() + PURCHASE_TICKET_TTL_MS
    }

    cb(true)
end

local function saveOwnedVehicle(src, vehicleProps, purchaseModel)
    local isValid, currentShopIndex = validateEventContext(src, {
        rateKey = 'set_vehicle_owned',
        rateMs = OWNED_SAVE_COOLDOWN_MS,
        requirePlayer = true,
        requireShopDistance = SHOP_SAVE_MAX_DISTANCE
    })
    if not isValid then
        return false
    end

    if type(vehicleProps) ~= 'table' or type(purchaseModel) ~= 'string' then
        return false
    end

    local lockKey = ('save_owned:%s'):format(src)
    if not lockAcquire(lockKey) then
        return false
    end

    local ok = false
    repeat
        pruneStateTables(false)

        local xPlayer = getPlayerCached(src)
        if not xPlayer then break end

        local identifier = xPlayer.getIdentifier and xPlayer.getIdentifier() or xPlayer.identifier
        if not identifier or identifier == '' then break end

        local ticket = purchaseTickets[src]
        if not ticket then break end
        if GetGameTimer() > (tonumber(ticket.expiresAt) or 0) then
            purchaseTickets[src] = nil
            break
        end

        local model = tostring(purchaseModel or '')
        if model == '' or model ~= tostring(ticket.model) then break end

        local cfg = vehCfg(model)
        if not cfg then break end

        local ticketShopIndex = tonumber(ticket.shopIndex)
        if ticketShopIndex and currentShopIndex ~= ticketShopIndex then
            break
        end

        local plate = normalizePlate(vehicleProps.plate)
        if plate == '' or isPlateOwnedByAnother(identifier, plate) then break end

        local expectedModelHash = GetHashKey(cfg.model)
        if type(vehicleProps.model) == 'number' and vehicleProps.model ~= expectedModelHash then
            break
        end

        vehicleProps.plate = plate
        vehicleProps.model = expectedModelHash

        local vehicleJson = json.encode(vehicleProps)
        local vehicleType = tostring(vehicleProps.type or 'car')
        local jobName = cfg.category
        local resolvedVehicleName = tostring(cfg.name or cfg.model or '')
        local healthVehicleJson = json.encode({
            engine = tonumber(vehicleProps.engineHealth) or 1000.0,
            fuel = tonumber(vehicleProps.fuelLevel) or 100.0,
            health_body = tonumber(vehicleProps.bodyHealth) or 1000.0,
            tyres = {},
            doors = {}
        })

        -- Writes are queued and flushed in background batches to reduce gameplay spikes.
        queueOwnedVehicleWrite({
            identifier = tostring(identifier),
            plate = plate,
            vehicleJson = vehicleJson,
            vehicleType = vehicleType,
            jobName = jobName,
            vehicleName = resolvedVehicleName,
            healthVehicleJson = healthVehicleJson
        })

        plateTakenCache[compactPlate(plate)] = {
            owner = tostring(identifier),
            expiresAt = GetGameTimer() + PLATE_CACHE_TTL_MS
        }

        purchaseTickets[src] = nil
        webhookTickets[src] = {
            model = tostring(cfg.model),
            plate = plate,
            expiresAt = GetGameTimer() + WEBHOOK_TICKET_TTL_MS
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
        ok = true
    until true

    lockRelease(lockKey)
    return ok
end

local function resolveWebhookUrl()
    local fromConvar = tostring(GetConvar('val_vehicleshop_webhook_buy', '') or '')
    if fromConvar ~= '' then return fromConvar end

    local strictConvarOnly = not not (Config and Config.Security and Config.Security.StrictWebhookConvarOnly)
    if strictConvarOnly then return '' end

    if Config['DiscordWebhook'] and Config['DiscordWebhook'].BuyVehicle then
        return tostring(Config['DiscordWebhook'].BuyVehicle)
    end

    return ''
end

local function webhookQueueSize()
    return Runtime.WEBHOOK_QUEUE.tail - Runtime.WEBHOOK_QUEUE.head + 1
end

local function snapshotWebhookQueue()
    local out = {}
    for i = Runtime.WEBHOOK_QUEUE.head, Runtime.WEBHOOK_QUEUE.tail do
        local item = Runtime.WEBHOOK_QUEUE.data[i]
        if item then out[#out + 1] = item end
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
    if Runtime.WEBHOOK_QUEUE.persistScheduled then return end
    Runtime.WEBHOOK_QUEUE.persistScheduled = true

    SetTimeout(1500, function()
        Runtime.WEBHOOK_QUEUE.persistScheduled = false
        if Runtime.WEBHOOK_QUEUE.dirty then
            persistWebhookQueue()
            Runtime.WEBHOOK_QUEUE.dirty = false
        end
    end)
end

local function enqueueWebhookRequest(item)
    if type(item) ~= 'table' then return end

    Runtime.WEBHOOK_QUEUE.tail = Runtime.WEBHOOK_QUEUE.tail + 1
    Runtime.WEBHOOK_QUEUE.data[Runtime.WEBHOOK_QUEUE.tail] = item
    Runtime.WEBHOOK_QUEUE.dirty = true
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

local function processWebhookQueue()
    if Runtime.WEBHOOK_QUEUE.inFlight then
        return WEBHOOK_WORKER_TICK_MS
    end

    local item = Runtime.WEBHOOK_QUEUE.data[Runtime.WEBHOOK_QUEUE.head]
    if not item then
        return WEBHOOK_IDLE_TICK_MS
    end

    local now = GetGameTimer()
    local nextAttemptAt = tonumber(item.nextAttemptAt) or 0
    if now < nextAttemptAt then
        return math.max(50, math.min(nextAttemptAt - now, WEBHOOK_IDLE_TICK_MS))
    end

    Runtime.WEBHOOK_QUEUE.inFlight = true

    PerformHttpRequest(item.url, function(statusCode, _responseBody, headers)
        local status = tonumber(statusCode) or 0

        if status >= 200 and status < 300 then
            Runtime.WEBHOOK_QUEUE.data[Runtime.WEBHOOK_QUEUE.head] = nil
            Runtime.WEBHOOK_QUEUE.head = Runtime.WEBHOOK_QUEUE.head + 1
            if Runtime.WEBHOOK_QUEUE.head > Runtime.WEBHOOK_QUEUE.tail then
                Runtime.WEBHOOK_QUEUE.head = 1
                Runtime.WEBHOOK_QUEUE.tail = 0
                Runtime.WEBHOOK_QUEUE.data = {}
            end
            Runtime.WEBHOOK_QUEUE.dirty = true
            scheduleWebhookPersist()
        else
            item.attempt = (tonumber(item.attempt) or 0) + 1
            local delayMs = nextRetryDelayMs(item.attempt, parseRetryAfterMs(headers))
            item.nextAttemptAt = GetGameTimer() + delayMs
            Runtime.WEBHOOK_QUEUE.dirty = true
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

        Runtime.WEBHOOK_QUEUE.inFlight = false
    end, 'POST', json.encode(item.body), { ['Content-Type'] = 'application/json' })

    return WEBHOOK_WORKER_TICK_MS
end

local function loadPersistedWebhookQueue()
    local raw = LoadResourceFile(Val, 'webhook_queue.json')
    if not raw or raw == '' then return end

    local ok, rows = pcall(json.decode, raw)
    if not ok or type(rows) ~= 'table' then return end

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

sendPurchaseWebhook = function(src, carKey, plate)
    local url = resolveWebhookUrl()
    if url == '' then return end

    local xPlayer = getPlayerCached(src)
    if not xPlayer then return end

    local cfg = vehCfg(carKey) or {}
    local carName = cfg.name or cfg.model or tostring(carKey)
    local model = cfg.model or tostring(carKey)
    local price = ESX.Math.GroupDigits(tonumber(cfg.price) or 0)
    local steamId = getSteamIdentifier(xPlayer)
    local discordIdentifier = getDiscordIdentifier(xPlayer)
    local discordUserId = getDiscordUserId(discordIdentifier)
    local discordName = GetPlayerName(src) or ('ID ' .. src)
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

    enqueueWebhookRequest({
        url = url,
        body = {
            username = 'VAL Legacy [LOG]',
            embeds = embed
        },
        attempt = 0,
        nextAttemptAt = GetGameTimer(),
        createdAt = GetGameTimer()
    })
end

CreateThread(function()
    fetchESX()

    ensureOwnedVehiclesIndex('owner', 'idx_owned_vehicles_owner')
    ensureOwnedVehiclesIndex('plate', 'idx_owned_vehicles_plate')

    ESX.RegisterServerCallback(CALLBACK_NAMESPACE .. ':isPlateTaken', cbIsPlateTaken)
    ESX.RegisterServerCallback(CALLBACK_NAMESPACE .. ':buyVehicle', cbBuyVehicle)

    if Val ~= CALLBACK_NAMESPACE then
        ESX.RegisterServerCallback(Val .. ':isPlateTaken', cbIsPlateTaken)
        ESX.RegisterServerCallback(Val .. ':buyVehicle', cbBuyVehicle)
    end

    loadPersistedWebhookQueue()
end)

-- Central scheduler: one lightweight loop for recurring background tasks.
Runtime.TASK_SCHEDULER = {
    { name = 'state_prune', interval = 2500, runAt = 0, fn = function() pruneStateTables(false) end },
    { name = 'write_queue_flush', interval = WRITE_QUEUE_IDLE_TICK_MS, runAt = 0, fn = flushWriteQueue },
    { name = 'webhook_worker', interval = WEBHOOK_WORKER_TICK_MS, runAt = 0, fn = processWebhookQueue }
}

CreateThread(function()
    while true do
        local now = GetGameTimer()
        local sleep = 1000

        for i = 1, #Runtime.TASK_SCHEDULER do
            local task = Runtime.TASK_SCHEDULER[i]
            if now >= (task.runAt or 0) then
                local nextInterval = task.fn()
                task.runAt = now + (tonumber(nextInterval) or task.interval)
            end
            local remaining = (task.runAt or now) - now
            if remaining > 0 and remaining < sleep then
                sleep = remaining
            end
        end

        Wait(math.max(50, sleep))
    end
end)

RegisterNetEvent(Val .. ':Vehicle:Test')
AddEventHandler(Val .. ':Vehicle:Test', function(carname)
    local src = source
    if not validateEventContext(src, {
        rateKey = 'test_drive',
        rateMs = TESTDRIVE_COOLDOWN_MS,
        requirePlayer = true,
        requireShopDistance = SHOP_INTERACTION_MAX_DISTANCE
    }) then
        return
    end

    if type(carname) ~= 'string' or carname == '' then return end

    local cfg = vehCfg(carname)
    if not cfg then return end

    local xPlayer = getPlayerCached(src)
    local shopIndex = findShopInRange(src, SHOP_INTERACTION_MAX_DISTANCE)
    local shopConfig = Config['ZONE_SHOP'] and Config['ZONE_SHOP'][shopIndex]
    if not shopAllowsJob(shopConfig, xPlayer) or not shopHasVehicle(shopConfig, cfg.model) then
        return
    end

    if JobsModule.canViewVehicle and (not JobsModule.canViewVehicle(xPlayer, cfg)) then
        return
    end

    local lockKey = ('testdrive:%s'):format(src)
    if not lockAcquire(lockKey) then
        return
    end

    leaveTestBucket(src)
    enterTestBucket(src)
    lockRelease(lockKey)

    TriggerClientEvent(Val .. ':TestCar:Client', src, carname)
end)

RegisterNetEvent(Val .. ':ExitTest')
AddEventHandler(Val .. ':ExitTest', function()
    local src = source
    if not validateEventContext(src, { rateKey = 'exit_test', rateMs = 500, requirePlayer = false }) then
        return
    end
    leaveTestBucket(src)
end)

RegisterNetEvent(CALLBACK_NAMESPACE .. ':setVehicleOwned')
AddEventHandler(CALLBACK_NAMESPACE .. ':setVehicleOwned', function(vehicleProps, _jobName, _vehicleName, purchaseModel)
    local src = source
    if type(vehicleProps) ~= 'table' then return end
    if type(purchaseModel) ~= 'string' then return end
    saveOwnedVehicle(src, vehicleProps, purchaseModel)
end)

if Val ~= CALLBACK_NAMESPACE then
    RegisterNetEvent(Val .. ':setVehicleOwned')
    AddEventHandler(Val .. ':setVehicleOwned', function(vehicleProps, _jobName, _vehicleName, purchaseModel)
        local src = source
        if type(vehicleProps) ~= 'table' then return end
        if type(purchaseModel) ~= 'string' then return end
        saveOwnedVehicle(src, vehicleProps, purchaseModel)
    end)
end

RegisterNetEvent(Val .. ':logVehiclePurchase')
AddEventHandler(Val .. ':logVehiclePurchase', function(carKey, plate)
    local src = source
    if not validateEventContext(src, {
        rateKey = 'log_purchase',
        rateMs = 1000,
        requirePlayer = true
    }) then
        return
    end

    if type(carKey) ~= 'string' or type(plate) ~= 'string' then
        return
    end

    pruneStateTables(false)

    local ticket = webhookTickets[src]
    local now = GetGameTimer()

    if not ticket then
        pendingWebhookRequests[src] = {
            model = tostring(carKey),
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
    local requestedModel = cfg and tostring(cfg.model) or tostring(carKey)
    local requestedPlate = normalizePlate(plate)

    if requestedModel ~= tostring(ticket.model) or requestedPlate ~= tostring(ticket.plate) then
        return
    end

    webhookTickets[src] = nil
    sendPurchaseWebhook(src, requestedModel, requestedPlate)
end)

AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    local src = tonumber(playerId)
    if not src then return end
    invalidatePlayerCache(src)
    if xPlayer and xPlayer.job and xPlayer.job.name then
        jobIndexSet(src, xPlayer.job.name)
    end
end)

AddEventHandler('esx:setJob', function(playerId, job)
    local src = tonumber(playerId)
    if not src then return end
    jobIndexSet(src, job and job.name or nil)
    invalidatePlayerCache(src)
end)

AddEventHandler('playerDropped', function()
    clearPlayerState(source)
    pruneStateTables(true)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= Val then return end

    for _, src in ipairs(GetPlayers()) do
        clearPlayerState(tonumber(src))
    end

    persistWebhookQueue()
    for _ = 1, 10 do
        if writeQueueSize() <= 0 then
            break
        end
        flushWriteQueue()
    end
end)
