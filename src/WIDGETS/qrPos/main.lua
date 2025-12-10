print("qrWidget version:", getVersion())
local TELE_PATH = "/SCRIPTS/TELEMETRY"
local qr = nil
local getGps = nil

local function dump(o)
	if type(o) == 'table' then
	   local s = '{ '
	   for k,v in pairs(o) do
		  if type(k) ~= 'number' then k = '"'..k..'"' end
		  s = s .. '['..k..'] = ' .. dump(v) .. ','
	   end
	   return s .. '} '
	else
	   return tostring(o)
	end
 end

local myoptions = {
	{ "COLOR", COLOR, BLACK },
	{ "linknone",   BOOL, 1 },
	{ "linkgeo",    BOOL, 0 },
	{ "linkgoogle", BOOL, 0 },
	{ "linkguru",   BOOL, 0 },
	{ "interval", VALUE, 100, 500 },
  }
local prefixes = { linknone = "", linkgeo = "geo:", linkgoogle = "comgooglemaps://?q=", linkguru = "GURU://" }

local function create(zone, options)
	print("qrWidget create:", dump(zone), dump(options), dump(qr))

	if qr == nil then
		print("qrWidget load:")
		qr = loadfile(TELE_PATH .. "/qrPos.lua")(false)
		print("qrWidget loaded", dump(qr))
		getGps = qr.getGps
		qr = qr.qr:new() --replaces prototype with instance to save memory
		collectgarbage()
	end
	return { zone=zone, options=options, loopc=0, loopEnd=-1000000, pxlSize=1 }
end

local function update(vars, newOptions)
	print("qrWidget update", dump(vars), dump(newOptions))
	if vars ~= nil then
		vars.options = newOptions
	end
end

local function background(vars)
	print("qrWidget bg", dump(vars))
end

local function refresh(vars)
    if qr == nil then
        print("qr is nil?")
        local zone = vars and vars.zone or {x=0, y=0, w=100, h=100}
        local options = vars and vars.options or myoptions
        local newVars = create(zone, options)
        for k, v in pairs(newVars) do
            vars[k] = v
        end
    end

    local prefix = ""
    for key, value in pairs(prefixes) do
        if vars.options[key] == 1 then
            prefix = value
            break
        end
    end
    local newStr = prefix .. getGps()

    -- Show instructions when no QR code is present
    if not qr.isvalid and not qr:isRunning() then
        lcd.drawText(vars.zone.x + vars.zone.w/2, vars.zone.y + vars.zone.h/2 - 10, "Generating...", CENTER + SMLSIZE + CUSTOM_COLOR)
        lcd.drawText(vars.zone.x + vars.zone.w/2, vars.zone.y + vars.zone.h/2, "or check GPS", CENTER + SMLSIZE + CUSTOM_COLOR)
    end

    if newStr ~= qr.inputstr and not qr:isRunning() and ((vars.loopc - vars.loopEnd) > (vars.options.interval or 100)) then
        print("qrWidget start", newStr)
        qr:start(newStr)
    end

	if qr:isRunning() then
		if qr:genframe(vars.str) then
			vars.loopEnd = vars.loopc
			vars.pxlSize = math.floor(math.min(vars.zone.w, vars.zone.h) / (qr.width + 2))
			print("qrWidget rendered", vars.pxlSize)
		else
			print("qrWidget genframe progress", qr.progress)
		end
	end

	if vars.options.COLOR ~= nil then lcd.setColor(CUSTOM_COLOR, vars.options.COLOR) end

	if qr.isvalid and getUsage() < 40 then
		qr:draw(vars.zone.x, vars.zone.y, vars.pxlSize, ERASE, CUSTOM_COLOR)
	end

	lcd.drawText(vars.zone.x, vars.zone.y + vars.zone.h - 10, newStr, LEFT + SMLSIZE + CUSTOM_COLOR);

	if (vars.loopc % 10 == 0) then print("render", vars.loopc, vars.pxlSize, vars.loopc - vars.loopEnd) end
	vars.loopc = vars.loopc + 1
end

return { name="qrLua", options=myoptions, create=create, update=update, refresh=refresh, background=background }
