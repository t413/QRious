local myoptions = {
    { "linkType", CHOICE, 2, { "text", "native", "google", "CoMaps", "Guru" } },
    { "textColor", COLOR, DARKBLUE },
}

local linkPrefixes = { "", "geo:", "comgooglemaps://?q=", "cm://map?ll=", "GURU://" }

local function getGps()
    local t = getTime() / 666
    if t > 10000 then
        -- temporary testing: return simulated position based on 37.87133,-122.31750
        local lat = 37.87133 + (t % 100) / 100000
        local lon = -122.31750 + (t % 130) / 100000
        return { lat = lat, lon = lon, valid = true, time = getTime() }
    end
    local gpsfield = getFieldInfo("GPS")
    local gps = gpsfield and getValue(gpsfield.id) or nil
    if type(gps) == "table" and gps.lat ~= nil and gps.lon ~= nil then
        return { lat = gps.lat, lon = gps.lon, valid = true, time = getTime() }
    end
    return { lat = 0, lon = 0, valid = false }
end

local function create(zone, options)
    return {
        zone = zone,
        options = options,
        lastValidGps = nil,
    }
end

local function drawOverlayMsg(zone, text)
    local strW, strH = lcd.sizeText(text, SMLSIZE)
    local boxW = strW + 16
    local boxH = strH + 6
    local boxX = zone.x + (zone.w - boxW) / 2
    local boxY = zone.y + (zone.h - boxH) / 2
    lcd.drawFilledRectangle(boxX, boxY, boxW, boxH, WHITE)
    lcd.drawRectangle(boxX, boxY, boxW, boxH, CUSTOM_COLOR, 2)
    lcd.drawText(zone.x + zone.w/2, boxY + 3, text, CENTER + SMLSIZE + CUSTOM_COLOR)
end

local function update(vars, newOptions)
    vars.options = newOptions
end

local function background(vars)
    local gpsData = getGps()
    if gpsData and gpsData.valid then
        vars.lastValidGps = gpsData
    end
end

local function refresh(vars)
    background(vars)
    local prefix = linkPrefixes[vars.options.linkType or 1] or 'geo:'
    local hasGps = vars.lastValidGps and vars.lastValidGps.valid

    local newStr = hasGps
        and prefix .. string.format("%.6f,%.6f", vars.lastValidGps.lat, vars.lastValidGps.lon)
        or prefix .. "no_gps"

    local age = hasGps and ((getTime() - vars.lastValidGps.time) / 100) or 0
    local underText = (age > 6) and string.format("outdated %.0fs", age) or nil

    lcd.setColor(CUSTOM_COLOR, vars.options.textColor or BLACK)

    if lvgl and lvgl.qrcode then
        local qrSize = math.min(vars.zone.w, vars.zone.h - 20) - 8
        local qrX = vars.zone.x + (vars.zone.w - qrSize) / 2
        local qrY = vars.zone.y + (vars.zone.h - qrSize) / 2

        lcd.drawFilledRectangle(qrX - 2, qrY - 2, qrSize + 4, qrSize + 4, WHITE)
        lvgl.qrcode({
            x = qrX, y = qrY, w = qrSize, h = qrSize,
            data = newStr
        })
    else
        lcd.drawText(vars.zone.x + vars.zone.w/2, vars.zone.y + vars.zone.h/2, "No LVGL QR", CENTER)
    end

    if underText then --draw below
        lcd.drawText(vars.zone.x + vars.zone.w/2, vars.zone.y + vars.zone.h - 15, underText, CENTER + SMLSIZE + CUSTOM_COLOR)
    end

    if not hasGps then
        drawOverlayMsg(vars.zone, "NO GPS")
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
