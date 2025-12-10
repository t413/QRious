-- QR Position Tool - wrapper for TOOLS menu
local toolName = "TNS|QR Position|TNE"

local function init()
    -- No initialization needed
end

local function run(event)
    chdir("/SCRIPTS/TELEMETRY")
    return "/SCRIPTS/TELEMETRY/qrPos.lua"
end

return { init=init, run=run }
