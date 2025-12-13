local TELE_PATH = "/SCRIPTS/TELEMETRY"
local qr = nil
local qrMutex = nil --reference to vars of active widget using qr module
local getGps = nil
local COUNT_PER_SEC = 20 --opentx seems to run at 20hz
local linkPrefixes = nil --set in create() from qrPos.lua

local myoptions = {
    { "linkType", CHOICE, 2, nil }, --populated later in create
    { "interval", VALUE, 10, 2, 60 }, --default, min, max (seconds)
    { "qrColor",   COLOR, BLUE },
    { "textColor", COLOR, DARKBLUE },
    { "qrBG",      COLOR, BLACK },
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
        qr = module.qr:new()
        myoptions[1][4] = module.linkLabels
        linkPrefixes = module.linkPrefixes
        collectgarbage()
    end
    return {
        zone = zone,
        options = options,
        pxlSize = 1,
        lastQrStr = nil,
        lastValidGps = nil,
        activeGps = nil,
        bmpObj, bmpPos = nil, nil
    }
end

function getMyQr(vars)
    return (qrMutex == nil or qrMutex == vars) and qr or nil
end

function drawBMP(qr, vars, btmPadding)
    if vars.bmpObj == nil or btmPadding ~= vars.bmpPos.btmPadding then
        if qr.bmpPath == nil then return end
        vars.bmpObj = vars.bmpObj or Bitmap.open(qr.bmpPath)
        local bmpW, bmpH = Bitmap.getSize(vars.bmpObj)
        local availW, availH = vars.zone.w, vars.zone.h - (btmPadding or 0)
        local scale = math.min(math.floor(availW / bmpW * 100), math.floor(availH / bmpH * 100))
        vars.bmpPos = {
            btmPadding = btmPadding,
            offsetX = vars.zone.x + (availW - bmpW * scale / 100) / 2,
            offsetY = vars.zone.y + (availH - bmpH * scale / 100) / 2,
            scale = scale
        }
    end
    lcd.drawBitmap(vars.bmpObj, vars.bmpPos.offsetX, vars.bmpPos.offsetY, vars.bmpPos.scale)
end

local function drawOverlayMsg(zone, text, barProgress, barMax)
    local strW, strH = lcd.sizeText(text, SMLSIZE)
    local boxW = strW + 16
    local boxH = barProgress and (strH + 14) or (strH + 6)
    local boxX = zone.x + (zone.w - boxW) / 2
    local boxY = zone.y + (zone.h - boxH) / 2
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH, WHITE)
    lcd.drawRectangle(boxX, boxY, boxW, boxH, CUSTOM_COLOR, 2)
    lcd.drawText(zone.x + zone.w/2, boxY + 3, text, CENTER + SMLSIZE + CUSTOM_COLOR)
    if barProgress and barMax then
        local barW, barX, barY = boxW - 16, boxX + 8, boxY + strH + 4
        lcd.drawRectangle(barX, barY, barW, 6)
        lcd.drawFilledRectangle(barX + 1, barY + 1, (barW - 2) * barProgress / barMax, 4, CUSTOM_COLOR)
    end
end
local function update(vars, newOptions)
    if vars ~= nil then
        vars.options = newOptions
        vars.activeGps = nil --force refresh
        vars.bmpObj = nil --force reload bmp
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
    background(vars) --gets latest gps data
    -- Determine which prefix to use (from options)
    local linkidx = vars.options.linkType
    local prefix = linkPrefixes[linkidx or 1] or 'geo:'
    -- Build QR string
    local newStr = (vars.lastValidGps and vars.lastValidGps.valid)
        and prefix .. string.format("%.6f,%.6f", vars.lastValidGps.lat, vars.lastValidGps.lon)
        or prefix .. "no gps"
    -- Check if we need to generate a new QR code
    local interval = (vars.options.interval or 10)
    local activeAge = (vars.activeGps ~= nil) and ((getTime() - vars.activeGps.time) / 100) or interval + 1
    local myqr = getMyQr(vars)
    if myqr and (newStr ~= vars.lastQrStr) and not qr:isRunning() and (activeAge > interval or not vars.bmpObj) then
        qrMutex = vars
        qr.fgColor, qr.bgColor = vars.options.qrColor, vars.options.qrBG
        qr:start(newStr)
        vars.lastQrStr, vars.activeGps = newStr, vars.lastValidGps
        qr.bmpPath = "/SCRIPTS/TELEMETRY/qr_temp.bmp" --enable bmp output
        print("Starting QR generation for: " .. newStr, activeAge, interval)
    end
    local underText = (activeAge > interval + 1) and string.format("outdated %.0fs", activeAge) or nil
    if underText then --draw below
        lcd.drawText(vars.zone.x + vars.zone.w/2, vars.zone.y + vars.zone.h - 15, underText, CENTER + SMLSIZE + CUSTOM_COLOR)
    end
    if myqr and qr:isRunning() then --do generation steps
        if qr:genframe() then -- Generation complete
            -- Calculate pixel size to fit in zone with padding
            vars.pxlSize = math.floor(math.min(vars.zone.w, vars.zone.h - 20) / (qr.width + 2))
            vars.bmpObj = nil --force reload bmp
            drawBMP(qr, vars) --saves context before releasing mutex
            qrMutex = nil
        end
    end
    -- Draw QR code or status
    lcd.setColor(CUSTOM_COLOR, vars.options.textColor or BLACK)
    if vars.bmpPos or qr.isvalid then -- Draw QR code, even the old one
        drawBMP(qr, vars, underText and 14 or 0)
    end
    -- now draw status overlays
    if myqr and qr:isRunning() then
        drawOverlayMsg(vars.zone, "Generating...", qr.progress or 0, 11)
    elseif vars.lastValidGps == nil or not vars.lastValidGps.valid then
        drawOverlayMsg(vars.zone, vars.lastValidGps and "Not set up" or "NO GPS")
    end
end

return {
    name = "qrLua",
    options = myoptions,
    create = create,
    update = update,
    refresh = refresh,
    background = background
}
