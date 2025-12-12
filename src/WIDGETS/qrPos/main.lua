local TELE_PATH = "/SCRIPTS/TELEMETRY"
local qr = nil
local getGps = nil
local COUNT_PER_SEC = 20 --opentx seems to run at 20hz

local myoptions = {
    { "COLOR", COLOR, BLACK },
    { "linknone",   BOOL, 0 },
    { "linkgeo",    BOOL, 1 },
    { "linkgoogle", BOOL, 0 },
    { "linkcomaps", BOOL, 0 },
    { "linkguru",   BOOL, 0 },
    { "interval", VALUE, 10, 60, 1 }, --default, max, min (seconds)
}

local prefixes = {
    linknone = "",
    linkgeo = "geo:",
    linkgoogle = "comgooglemaps://?q=",
    linkcomaps = "cm://map?ll=",
    linkguru = "GURU://"
}

local function create(zone, options)
    if qr == nil then
        local module = loadfile(TELE_PATH .. "/qrPos.lua")(false)
        getGps = module.getGps
        qr = module.qr:new({lowMem = false})  -- high speed mode
        collectgarbage()
    end
    return {
        zone = zone,
        options = options,
        loopc = 0,
        startQRc = -10000,
        pxlSize = 1,
        lastValidGps = nil,
        activeGps = nil,
    }
end

local function update(vars, newOptions)
    if vars ~= nil then
        vars.options = newOptions
        -- Force regeneration on option change
        qr:reset()
        vars.startQRc = -10000
    end
end

local function background(vars) -- Update GPS in background
    local gpsData = getGps and getGps() or nil
    if gpsData and gpsData.valid then
        vars.lastValidGps = gpsData
    end
end

local function refresh(vars)
    if qr == nil or getGps == nil then
        local newVars = create(vars.zone, vars.options)
        for k, v in pairs(newVars) do
            vars[k] = v
        end
        print("QR module not initialized")
        return
    end
    -- Update GPS data
    local gpsData = getGps()
    if gpsData and gpsData.valid then
        vars.lastValidGps = gpsData
    end
    -- Determine which prefix to use (from options)
    local prefix = ""
    for key, value in pairs(prefixes) do
        if vars.options[key] == 1 then
            prefix = value
            break
        end
    end
    -- Build QR string
    local newStr = (vars.lastValidGps and vars.lastValidGps.valid)
        and prefix .. string.format("%.6f,%.6f", vars.lastValidGps.lat, vars.lastValidGps.lon)
        or prefix .. "no gps"
    -- Check if we need to generate a new QR code
    local agesrc = vars.activeGps or vars.lastValidGps
    local age = agesrc and ((getTime() - agesrc.time) / 100) or 0
    local interval = (vars.options.interval or 10)
    if newStr ~= qr.inputstr and not qr:isRunning() and (age > interval or qr.inputstr == "") then
        qr:start(newStr)
        vars.startQRc, vars.activeGps = vars.loopc, vars.lastValidGps
        qr.bmpPath = "/SCRIPTS/TELEMETRY/qr_temp.bmp" --enable bmp output
        print("Starting QR generation for: " .. newStr, age, interval)
    end
    if qr:isRunning() then --do generation steps
        if qr:genframe() then -- Generation complete
            -- Calculate pixel size to fit in zone with padding
            vars.pxlSize = math.floor(math.min(vars.zone.w, vars.zone.h - 20) / (qr.width + 2))
        end
    end
    -- Set custom color if specified
    if vars.options.COLOR ~= nil then
        lcd.setColor(CUSTOM_COLOR, vars.options.COLOR)
    end
    print("QR refresh", vars.loopc, newStr, qr:isRunning() and "running" or "idle", qr.isvalid and "valid" or "invalid", age, interval)
    -- Draw QR code or status
    if qr:isRunning() then
        -- Show generation progress
        lcd.drawText(vars.zone.x + vars.zone.w/2, vars.zone.y + vars.zone.h/2 - 20, "Generating...", CENTER + SMLSIZE + CUSTOM_COLOR)
        local progress = qr.progress or 0
        local barW = math.min(vars.zone.w - 20, 100)
        local barX = vars.zone.x + (vars.zone.w - barW) / 2
        lcd.drawRectangle(barX, vars.zone.y + vars.zone.h/2, barW, 6)
        lcd.drawFilledRectangle(barX + 1, vars.zone.y + vars.zone.h/2 + 1, (barW - 2) * progress / 10, 4, CUSTOM_COLOR)
    elseif qr.isvalid then
        -- Draw QR code
        local qrArea = math.min(vars.zone.w, vars.zone.h - 20)
        local scale = math.floor(qrArea / qr.width * 100)
        local offsetX = vars.zone.x + (vars.zone.w - qr.width * scale / 100) / 2
        local offsetY = vars.zone.y + (vars.zone.h - 20 - qr.width * scale / 100) / 2
        qr:drawBMP(offsetX, offsetY, scale)
    elseif vars.lastValidGps == nil or not vars.lastValidGps.valid then
        -- No valid QR code yet
        lcd.drawText(vars.zone.x + vars.zone.w/2, vars.zone.y + vars.zone.h/2 - 10, "Waiting for GPS", CENTER + SMLSIZE + CUSTOM_COLOR)
    end

    -- Draw info text below QR code
    local textY = vars.zone.y + vars.zone.h - 15
    -- Show GPS coordinates or status
    if not vars.lastValidGps or not vars.lastValidGps.valid then
        local msg = vars.lastValidGps and "not setup" or "NO GPS"
        lcd.drawText(vars.zone.x + vars.zone.w/2, textY, msg, CENTER + SMLSIZE + CUSTOM_COLOR)
    else
        -- Show age of data
        local ageText = string.format("%.0fs old", age)
        lcd.drawText(vars.zone.x + vars.zone.w/2, textY, ageText, CENTER + SMLSIZE + CUSTOM_COLOR)
    end
    vars.loopc = vars.loopc + 1
end

return {
    name = "qrLua",
    options = myoptions,
    create = create,
    update = update,
    refresh = refresh,
    background = background
}
