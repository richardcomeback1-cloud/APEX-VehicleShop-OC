local NumberCharset = {}
local Charset = {}

for i = 48, 57 do NumberCharset[#NumberCharset + 1] = string.char(i) end
for i = 65, 90 do Charset[#Charset + 1] = string.char(i) end
for i = 97, 122 do Charset[#Charset + 1] = string.char(i) end

local function buildRandomFromCharset(length, source)
    local out = {}
    for i = 1, length do
        out[i] = source[math.random(1, #source)]
    end
    return table.concat(out)
end

function GeneratePlate()
    local maxAttempts = 15

    for _ = 1, maxAttempts do
        local generatedPlate = string.upper(buildRandomFromCharset(Config.PlateLetters, Charset) .. (Config.PlateUseSpace and ' ' or '') .. buildRandomFromCharset(Config.PlateNumbers, NumberCharset))
        if not IsPlateTaken(generatedPlate) then
            return generatedPlate
        end
    end

    -- Fallback with additional entropy if collisions are too high.
    return string.upper(buildRandomFromCharset(Config.PlateLetters, Charset) .. (Config.PlateUseSpace and ' ' or '') .. buildRandomFromCharset(Config.PlateNumbers + 1, NumberCharset))
end

function IsPlateTaken(plate)
    local p = promise.new()
    ESX.TriggerServerCallback(Val .. ':isPlateTaken', function(isPlateTaken)
        p:resolve(isPlateTaken)
    end, plate)

    return Citizen.Await(p)
end

function GetRandomNumber(length)
    return buildRandomFromCharset(length, NumberCharset)
end

function GetRandomLetter(length)
    return buildRandomFromCharset(length, Charset)
end
