local FILE_PATH = "/SCRIPTS/TELEMETRY"
if getUsage == nil then --not simulator
    if not bit32 ~= nil then
        load("bit32={band=function(a,b) return a&b end,bor=function(a,b)return a|b end,bxor=function(a,b) return a~b end,bnot=function(a) return ~a end,rshift=function(a,n) return a>>n end,lshift=function(a,n)  return a<<n end}")()
    end
end

-- Lookup tables as module-level constants, trimmed to support only versions 1-4 (MAX_QR_VERSION = 4)
local GLOG_LOOKUP = "\255\000\001\025\0022\026\198\003\2233\238\027h\199K\004d\224\0144\141\239\129\028\193i\248\200\008Lq\005\138e/\225$\015\0335\147\142\218\240\018\130E\029\181\194}j'\249\185\201\154\009xM\228r\166\006\191\139bf\2210\253\226\152%\179\016\145\034\1366\208\148\206\143\150\219\189\241\210\019\092\1318F@\030B\182\163\195H~nk:(T\250\133\186=\202^\155\159\010\021y+N\212\229\172s\243\167W\007p\192\247\140\128c\013gJ\222\2371\197\254\024\227\165\153w&\184\180|\017D\146\217#\032\137.7?\209[\149\188\207\205\144\135\151\178\220\252\190a\242V\211\171\020*]\158\132<9SGmA\162\031-C\216\183{\164v\196\023I\236\127\012o\246l\161;R)\157U\170\251`\134\177\187\204>Z\203Y_\176\156\169\160Q\011\245\022\235zu,\215O\174\213\233\230\231\173\232t\214\244\234\168PX\175"
local GEXP_LOOKUP = "\001\002\004\008\016\032@\128\029:t\232\205\135\019&L\152-Z\180u\234\201\143\003\006\012\0240`\192\157'N\156%J\1485j\212\181w\238\193\159#F\140\005\010\020(P\160]\186i\210\185o\222\161_\190a\194\153/^\188e\202\137\015\030<x\240\253\231\211\187k\214\177\127\254\225\223\163[\182q\226\217\175C\134\017\034D\136\013\0264h\208\189g\206\129\031>|\248\237\199\147;v\236\197\1513f\204\133\023.\092\184m\218\169O\158\033B\132\021*T\168M\154)R\164U\170I\1469r\228\213\183s\230\209\191c\198\145?~\252\229\215\179{\246\241\255\227\219\171K\1501b\196\1497n\220\165W\174A\130\0252d\200\141\007\014\0288p\224\221\167S\166Q\162Y\178y\242\249\239\195\155+V\172E\138\009\018$H\144=z\244\245\247\243\251\235\203\139\011\022,X\176}\250\233\207\131\0276l\216\173G\142\000"
local ECCBLOCKS_LOOKUP = "\001\000\019\007\001\000\016\010\001\000\013\013\001\000\009\017\001\000\034\010\001\000\028\016\001\000\022\022\001\000\016\028\001\0007\015\001\000,\026\002\000\017\018\002\000\013\022\001\000P\020\002\000\032\018\002\002\015\018\002\002\011\022"
local ADELTA_LOOKUP = "\000\011\015\019\023"
local FMTWORD_LOOKUP = {
    0x77c4, 0x72f3, 0x7daa, 0x789d, 0x662f, 0x6318, 0x6c41, 0x6976, --L
    0x5412, 0x5125, 0x5e7c, 0x5b4b, 0x45f9, 0x40ce, 0x4f97, 0x4aa0, --M
    0x355f, 0x3068, 0x3f31, 0x3a06, 0x24b4, 0x2183, 0x2eda, 0x2bed, --Q
    0x1689, 0x13be, 0x1ce7, 0x19d0, 0x0762, 0x0255, 0x0d0c, 0x083b  --H
}

local MAX_QR_VERSION = 4  -- Version 4 = 33x33, sufficient for GPS with any prefix

Qr = {
    eccbuf    = {},
    frame     = {},
    framask   = {}, --is masked lookup
    genpoly   = {},
    ecclevel  = 1,
    version   = 0,
    width     = 0,
    neccblk1  = 0,
    neccblk2  = 0,
    datablkw  = 0,
    eccblkwid = 0,
    maxlength = nil,
    inputstr  = "",
    isvalid   = false,
    progress  = nil,
    resume    = nil --continuation data store
}

function Qr:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    self:reset()
    return o
end

function Qr:start(str)
    self:reset()
    self.inputstr = str
    self.progress = 0
end

function Qr:isRunning()
    return self.progress ~= nil
end

function Qr:reset(partial)
    self.eccbuf, self.framask, self.genpoly = {}, {}, {}
    self.isvalid, self.progress, self.resume = false, nil, nil
    if partial == nil then
        self.frame, self.width = {}, 0
    end
end

--black to qrframe, white to mask (later black frame merged to mask)
function Qr:putalign(x, y)
    self.frame[x + self.width * y] = true
    for j = -2, 2 - 1 do
        self.frame[(x + j)     + self.width * (y - 2    )] = true;
        self.frame[(x - 2)     + self.width * (y + j + 1)] = true;
        self.frame[(x + 2)     + self.width * (y + j    )] = true;
        self.frame[(x + j + 1) + self.width * (y + 2    )] = true;
    end
    for j = 0, 2 - 1 do
        self:setmask(x - 1, y + j);
        self:setmask(x + 1, y - j);
        self:setmask(x - j, y - 1);
        self:setmask(x + j, y + 1);
    end
end

--Bit shift modnn
function Qr:modnn(x)
    while x >= 255 do
        x = x - 255
        x = bit32.rshift(x, 8) + bit32.band(x, 255)
    end
    return x
end

--set bit to indicate cell in qrframe is immutable
function Qr:setmask(x, y)
    local bt
    if x > y then
        bt = x
        x = y
        y = bt
    end
    -- y*y = 1+3+5...
    bt = bit32.rshift((y * y) + y, 1) + x
    self.framask[bt] = true
end

-- check mask - since symmetrical use half
function Qr:ismasked(x, y)
    local bt
    if x > y then
        bt = x
        x = y
        y = bt
    end
    bt = bit32.rshift((y * y) + y, 1) + x
    return self.framask[bt] == true
end

-- Apply the selected mask out of the 8.
function Qr:applymask(m)
    -- Only mask pattern 0 is used (m parameter ignored)
    for y = 0, self.width - 1 do
        for x = 0, self.width - 1 do
            if bit32.band((x + y), 1) == 0 and not self:ismasked(x, y) then
                -- Inline xorEqls
                self.frame[x + y * self.width] = (self.frame[x + y * self.width] ~= true) and true or nil
            end
        end
    end
end

--Generate QR frame array
function Qr:genframe()
    if self.progress == 0 then
        self.progress = 1
    end

    if self.progress == 1 then --determine version
        if self.resume == nil then self.resume = {vsn = 0} end
        for vsn = self.resume.vsn, MAX_QR_VERSION do
            if getUsage() > 60 then
                self.resume.vsn = vsn
                return
            end
            local k = (self.ecclevel - 1) * 4 + (vsn - 1) * 16
            self.neccblk1 = string.byte(ECCBLOCKS_LOOKUP, math.max(1, k + 1))
            self.neccblk2 = string.byte(ECCBLOCKS_LOOKUP, math.max(1, k + 2))
            self.datablkw = string.byte(ECCBLOCKS_LOOKUP, math.max(1, k + 3))
            self.eccblkwid = string.byte(ECCBLOCKS_LOOKUP, math.max(1, k + 4))
            k = self.datablkw * (self.neccblk1 + self.neccblk2) + self.neccblk2 - 3 + (self.version <= 9 and 1 or 0)
            if #self.inputstr <= k then
                self.version = vsn
                break
            end
        end
        self.resume = nil
        self.width = 17 + 4 * self.version
        print(string.format("QR: finished calculating version [%d] width [%d] from data len [%d]", self.version, self.width, #self.inputstr))
        self.progress = 2
        if getUsage() > 50 then return end
    end

    if self.progress == 2 then --initialize frame and eccbuf
        local eccbufLen = self.datablkw + (self.datablkw + self.eccblkwid) * (self.neccblk1 + self.neccblk2) + self.neccblk2
        for t = 0, eccbufLen - 1 do
            self.eccbuf[t] = 0
        end
        self.progress = 3
        if getUsage() > 50 then return end
    end

    if self.progress == 3 then --insert finder patterns and alignment blocks
        -- insert finders - black to frame, white to mask
        for t = 0, 2 do
            local k, y = 0, 0
            if t == 1 then k = self.width - 7 end
            if t == 2 then y = self.width - 7 end
            self.frame[(y + 3) + self.width * (k + 3)] = true
            for x = 0, 5 do
                self.frame[(y + x) + self.width * k] = true
                self.frame[y + self.width * (k + x + 1)] = true
                self.frame[(y + 6) + self.width * (k + x)] = true
                self.frame[(y + x + 1) + self.width * (k + 6)] = true
            end
            for x = 1, 4 do
                self:setmask(y + x, k + 1)
                self:setmask(y + 1, k + x + 1)
                self:setmask(y + 5, k + x)
                self:setmask(y + x + 1, k + 5)
            end
            for x = 2, 3 do
                self.frame[(y + x) + self.width * (k + 2)] = true
                self.frame[(y + 2) + self.width * (k + x + 1)] = true
                self.frame[(y + 4) + self.width * (k + x)] = true
                self.frame[(y + x + 1) + self.width * (k + 4)] = true
            end
        end
        -- alignment blocks
        if self.version > 1 then
            local t = string.byte(ADELTA_LOOKUP, math.max(1, self.version + 1))
            local y = self.width - 7
            while true do
                for x = self.width - 7, t - 3, -t do
                    self:putalign(x, y)
                end
                if y <= t + 9 then break end
                self:putalign(6, y)
                self:putalign(y, 6)
            end
        end
        self.progress = 4
        if getUsage() > 50 then return end
    end

    if self.progress == 4 then --add timing patterns and reserve format area
        self.frame[8 + self.width * (self.width - 8)] = true
        -- timing gap and reserve format area - mask only
        for i = 0, 8 do
            if i < 7 then
                self:setmask(7, i)
                self:setmask(self.width - 8, i)
                self:setmask(7, i + self.width - 7)
            end
            if i < 8 then
                self:setmask(i, 7)
                self:setmask(i + self.width - 8, 7)
                self:setmask(i, self.width - 8)
                self:setmask(i + self.width - 8, 8)
                self:setmask(8, i)
            end
            self:setmask(i, 8)
            if i < 7 then self:setmask(8, i + self.width - 7) end
        end
        -- timing row/col
        for x = 0, self.width - 15, 2 do
            self:setmask(9 + x, 6)
            self:setmask(6, 9 + x)
            self.frame[(8 + x) + self.width * 6] = true
            self.frame[6 + self.width * (8 + x)] = true
        end
        -- sync mask bits
        for y = 0, self.width - 1 do
            for x = 0, y do
                if self.frame[x + self.width * y] == true then
                    self:setmask(x, y)
                end
            end
        end
        self.progress = 5
        if getUsage() > 50 then return end
    end

    if self.progress == 5 then --encode data
        local v = #self.inputstr
        for i = 0, v - 1 do
            self.eccbuf[i] = string.byte(self.inputstr, i + 1)
        end
        self.maxlength = self.datablkw * (self.neccblk1 + self.neccblk2) + self.neccblk2
        if v >= self.maxlength - 2 then
            v = self.maxlength - 2
            if self.version > 9 then v = v - 1 end
        end
        if self.version > 9 then --not supported, error
            self.progress = nil
            return
        end
        -- shift and repack to insert length prefix
        local i = v
        self.eccbuf[i + 1], self.eccbuf[i + 2] = 0, 0
        while i > 0 do
            i = i - 1
            local t = self.eccbuf[i]
            self.eccbuf[i + 2] = bit32.bor(self.eccbuf[i + 2], bit32.band(255, bit32.lshift(t, 4)))
            self.eccbuf[i + 1] = bit32.rshift(t, 4)
        end
        self.eccbuf[1] = bit32.bor(self.eccbuf[1], bit32.band(255, bit32.lshift(v, 4)))
        self.eccbuf[0] = bit32.bor(0x40, bit32.rshift(v, 4))

        -- fill to end with pad pattern
        for i = v + 3 - (self.version < 10 and 1 or 0), self.maxlength - 1, 2 do
            self.eccbuf[i], self.eccbuf[i + 1] = 0xec, 0x11
        end
        self.progress = 6
        collectgarbage()
        if getUsage() > 50 then return end
    end

    if self.progress == 6 then --generate ECC
        if self.resume == nil then
            self.genpoly[0] = 1
            self.resume = {i=0, j=0}
        end
        local tmp = self.resume
        for i = tmp.i, self.eccblkwid - 1 do
            tmp.i = i
            if getUsage() > 40 then return end
            self.genpoly[i + 1] = 1
            for j = i, 1, -1 do
                local glog_val = self.genpoly[j] >= 1 and string.byte(GLOG_LOOKUP, math.max(1, 1 + self.genpoly[j]))
                self.genpoly[j] = glog_val and bit32.bxor(self.genpoly[j - 1], string.byte(GEXP_LOOKUP, math.max(1, 1 + self:modnn(glog_val + i)))) or self.genpoly[j - 1]
            end
            local glog_val = string.byte(GLOG_LOOKUP, math.max(1, 1 + self.genpoly[0]))
            self.genpoly[0] = string.byte(GEXP_LOOKUP, math.max(1, 1 + self:modnn(glog_val + i)))
        end
        for j = tmp.j, self.eccblkwid do
            tmp.j = j
            if getUsage() > 40 then return end
            self.genpoly[j] = string.byte(GLOG_LOOKUP, math.max(1, 1 + self.genpoly[j]))
        end
        self.resume = nil
        self.progress = 7
        collectgarbage()
        if getUsage() > 50 then return end
    end

    if self.progress == 7 then --append ecc to data buffer
        if self.resume == nil then
            self.resume = {blk=0, j=0, k=self.maxlength, y=0, id=nil}
        end
        local tmp = self.resume
        for blk = tmp.blk, 1 do
            for j = tmp.j, (blk == 0 and self.neccblk1 or self.neccblk2) - 1 do
                if tmp.id == nil then
                    for id = 0, self.eccblkwid - 1 do
                        self.eccbuf[tmp.k + id] = 0
                    end
                    tmp.id = 0
                end
                for id = tmp.id, self.datablkw + blk - 1 do
                    tmp.id = id
                    if getUsage() > 60 then return end
                    local xor_val = bit32.bxor(self.eccbuf[tmp.y + id], self.eccbuf[tmp.k])
                    local fb = xor_val < 255 and string.byte(GLOG_LOOKUP, xor_val + 1) or nil
                    if fb and fb ~= 255 then
                        for jd = 1, self.eccblkwid - 1 do
                            self.eccbuf[tmp.k + jd - 1] = bit32.bxor(self.eccbuf[tmp.k + jd], string.byte(GEXP_LOOKUP, 1 + self:modnn(fb + self.genpoly[self.eccblkwid - jd])))
                        end
                        self.eccbuf[tmp.k + self.eccblkwid - 1] = string.byte(GEXP_LOOKUP, 1 + self:modnn(fb + self.genpoly[0]))
                    else
                        for jd = tmp.k, tmp.k + self.eccblkwid - 2 do
                            self.eccbuf[jd] = self.eccbuf[jd + 1]
                        end
                        self.eccbuf[tmp.k + self.eccblkwid - 1] = 0
                    end
                end
                tmp.id = nil
                tmp.y = tmp.y + self.datablkw + blk
                tmp.k = tmp.k + self.eccblkwid
                tmp.j = j
            end
            tmp.blk = blk
        end
        self.resume = nil
        self.genpoly = nil  -- Clear generator polynomial, no longer needed
        self.progress = 8
        collectgarbage()
        if getUsage() > 50 then return end
    end

    if self.progress == 8 then --interleave data+ECC bytes blocks
        local tempbuf, y = {}, 0
        for i = 0, self.datablkw - 1 do
            for j = 0, self.neccblk1 - 1 do
                tempbuf[y] = self.eccbuf[i + j * self.datablkw]
                y = y + 1
            end
            for j = 0, self.neccblk2 - 1 do
                tempbuf[y] = self.eccbuf[(self.neccblk1 * self.datablkw) + i + (j * (self.datablkw + 1))]
                y = y + 1
            end
        end
        for j = 0, self.neccblk2 - 1 do
            tempbuf[y] = self.eccbuf[(self.neccblk1 * self.datablkw) + self.datablkw - 1 + (j * (self.datablkw + 1))]
            y = y + 1
        end
        for i = 0, self.eccblkwid - 1 do
            for j = 0, self.neccblk1 + self.neccblk2 - 1 do
                tempbuf[y] = self.eccbuf[self.maxlength + i + j * self.eccblkwid]
                y = y + 1
            end
        end
        self.eccbuf = tempbuf
        self.progress = 9
        collectgarbage()
        if getUsage() > 50 then return end
    end

    if self.progress == 9 then --pack bits into frame avoiding masked area
        if self.resume == nil then
            self.resume = {x = self.width - 1, y = self.width - 1, v = true, k = true, i = 0}
        end
        local tmp = self.resume
        local m = (self.datablkw + self.eccblkwid) * (self.neccblk1 + self.neccblk2) + self.neccblk2
        for i = tmp.i, m - 1 do
            tmp.i = i
            if getUsage() > 80 then return end
            local t = self.eccbuf[i]
            for j = 0, 7 do
                if bit32.band(0x80, t) >= 1 then
                    self.frame[tmp.x + self.width * tmp.y] = true
                end
                repeat   -- find next fill position
                    if tmp.v then tmp.x = tmp.x - 1 else
                        tmp.x = tmp.x + 1
                        if tmp.k then
                            if tmp.y ~= 0 then tmp.y = tmp.y - 1 else
                                tmp.x, tmp.k = tmp.x - 2, false
                                if tmp.x == 6 then tmp.x, tmp.y = 5, 9 end
                            end
                        else
                            if tmp.y ~= self.width - 1 then tmp.y = tmp.y + 1 else
                                tmp.x, tmp.k = tmp.x - 2, true
                                if tmp.x == 6 then tmp.x, tmp.y = 5, tmp.y - 8 end
                            end
                        end
                    end
                    tmp.v = not tmp.v
                until not self:ismasked(tmp.x, tmp.y)
                t = bit32.lshift(t, 1)
            end
        end
        self.eccbuf = nil  -- Clear eccbuf, no longer needed
        self.resume = nil
        self.progress = 10
        collectgarbage()
        if getUsage() > 50 then return end
    end

    if self.progress == 10 then --apply mask pattern
        collectgarbage()
        if self.resume == nil then self.resume = 0 end
        for y = self.resume, self.width - 1 do
            self.resume = y
            if getUsage() > 60 then return end
            for x = 0, self.width - 1 do
                if bit32.band((x + y), 1) == 0 and not self:ismasked(x, y) then
                    local idx = x + y * self.width
                    self.frame[idx] = (self.frame[idx] ~= true) and true or nil
                end
            end
        end
        self.framask = nil
        collectgarbage()
        self.resume = nil
        -- add in final mask/ecclevel bytes
        local y = FMTWORD_LOOKUP[1 + bit32.lshift(0 + (self.ecclevel - 1), 3)]
        for bit = 0, 7 do
            if bit32.band(y, 1) == 1 then
                self.frame[(self.width - 1 - bit) + self.width * 8] = true
                self.frame[8 + self.width * (bit + (bit < 6 and 0 or 1))] = true
            end
            y = bit32.rshift(y, 1)
        end
        for bit = 0, 6 do
            if bit32.band(y, 1) == 1 then
                self.frame[8 + self.width * (self.width - 7 + bit)] = true
                self.frame[((bit >= 1) and (6 - bit) or 7) + self.width * 8] = true
            end
            y = bit32.rshift(y, 1)
        end
        self.progress = 0
        self:reset(true) --partial reset, don't reset frame & width
        self.isvalid = true
        collectgarbage()
        return self.isvalid
    end
end

function Qr:draw(x, y, pxlSize, bgFlags, fgFlags)
    if lcd == nil then return end
    pxlSize = pxlSize or 2
	lcd.drawFilledRectangle(x, y, (self.width + 2) * pxlSize, (self.width + 2) * pxlSize, bgFlags or ERASE)
	for idx, value in pairs(self.frame) do
		if (value == true) then
			lcd.drawFilledRectangle(x + idx % self.width * pxlSize + pxlSize, y + math.floor(idx / self.width) * pxlSize + pxlSize, pxlSize, pxlSize, fgFlags or CUSTOM_COLOR)
		end
	end
end

local loopc = 0
local ctx = {
    loopStart = 0, loopEnd = 0,
    lastValid = 0,
    lastValidPos = "no gps",
    pxlSize = 2,
    qr = nil
}
local prefixes = { "", "geo:", "comgooglemaps://?q=", "GURU://" }
local prefixIndex = 1
local doRedraw = true
local continuous = false
local continuousFrameInterval = 50 --in loopc (10 loopc = 1 second)
local gpsfield = nil
local lastBGloopc = 0

local function getGps()
    if gpsfield == nil then
        gpsfield = getFieldInfo("GPS")
    end
    if gpsfield ~= nil then
        local gps = getValue(gpsfield.id)
        if type(gps) == "table" and gps.lat ~= nil and gps.lon ~= nil then
            return string.format("%.6f,%.6f", gps.lat, gps.lon)
        else
            return nil
        end
    else
        return "no gps sensor"
    end
end

function truncateStr(str, maxLen)
    if #str > maxLen then
        return string.sub(str, 1, maxLen - 2) .. ".."
    else
        return str
    end
end

local function init()
    ctx.qr = Qr:new() --creates instance from prototype
    Qr = nil --delete prototype
end

local function background()
    if lastBGloopc == loopc and not doRedraw then
        doRedraw = true
        ctx.qr:reset()
    end
    local location = getGps()
    if location ~= nil then
        ctx.lastValidPos = location
    end
    lastBGloopc = loopc
end

local function run(event)
    loopc = loopc + 1
    if lcd ~= nil then
        if doRedraw or ctx.qr:isRunning() then
            lcd.clear()
        else
            lcd.drawFilledRectangle(0, LCD_H - 8, LCD_W, 8, ERASE)
        end
        local location = getGps()
        if location ~= nil then
            ctx.lastValidPos = location
        end
        local newStr = prefixes[prefixIndex] .. (location or ctx.lastValidPos)
        local nextrender = continuousFrameInterval - (loopc - ctx.loopStart)
        local qrUpToDate = ctx.qr.isvalid and (newStr == ctx.qr.inputstr)
        if qrUpToDate then
            lastValid = loopc
        elseif ctx.qr.isvalid then --display time since last valid QR in top
            local dt = string.format("*%d", (loopc - lastValid) / 10) --in seconds
            lcd.drawText(0, 0, dt, SMLSIZE)
        end
        if continuous and (not qrUpToDate) and (not ctx.qr:isRunning()) and (nextrender <= 1) then
            event = EVT_ENTER_BREAK --simulate enter press to redraw qr
        end
        -- Always show current string at bottom
        local displayStr = truncateStr(((location == nil) and "[X]" or "") .. newStr, math.floor(LCD_W / 5))
        lcd.drawText(LCD_W / 2, LCD_H - 8, displayStr, SMLSIZE + CENTER)

        if ctx.qr:isRunning() and not continuous then -- Show progress bar
            lcd.drawGauge(LCD_W/4, LCD_H - 14, LCD_W/2, 5, ctx.qr.progress, 10) --x,y,width,height, value, maxvalue
        elseif ctx.qr.isvalid and doRedraw then -- Show generated QR
            doRedraw = false
            local qrXoffset = math.floor((LCD_W - ctx.pxlSize * (ctx.qr.width + 2)) / 2)
            ctx.qr:draw(qrXoffset, 0, ctx.pxlSize)
        elseif doRedraw then -- Show waiting/instruction screen
            local centerX = LCD_W / 2
            if continuous then
                lcd.drawText(centerX, LCD_H / 2, "<auto in " .. (nextrender/10) .. ">", SMLSIZE + CENTER)
            else
                lcd.drawText(centerX, 8, "QR Gen", MIDSIZE + CENTER)
                lcd.drawText(centerX, 22, "[enter] = once [menu]=auto", SMLSIZE + CENTER)
                lcd.drawText(centerX, 32, "<+/-> Change link type", SMLSIZE + CENTER)
            end
        end

        --handle events
        if event == EVT_ENTER_BREAK then
            ctx.qr:start(newStr)
            ctx.loopStart, lastValid = loopc, loopc
        elseif event == EVT_VIRTUAL_MENU or event == EVT_ENTER_LONG then
            continuous = not continuous
            ctx.qr:reset()
            doRedraw = true
            print("continuous mode " .. (continuous and "on" or "off"))
        elseif event == EVT_EXIT_BREAK then
            doRedraw = true
        elseif event == EVT_VIRTUAL_INC then
            prefixIndex = math.min(prefixIndex + 1, #prefixes)
            -- ctx.qr:reset() TODO TEMPORARY for pretending new coords
            doRedraw = true
        elseif event == EVT_VIRTUAL_DEC then
            prefixIndex = math.max(prefixIndex - 1, 1)
            -- ctx.qr:reset() TODO TEMPORARY
            doRedraw = true
        end
    end

    if lcd == nil then --desktop mode!
        if loopc > 100 then return 1 end --limit total looping in case there's a bug
        if ctx.qr.progress == nil then
            ctx.qr:start(arg[1] or "hello world")
        end
        function printFrame(buffer, width, back, fill)
            back = back or "  "
            fill = fill or "##"
            for i = -2, width + 1 do
                local line = ""
                for j = 0, width - 1 do
                    if i < 0 or i >= width then
                        line = line .. back
                    else
                        line = line .. ((buffer[j * width + i] == true) and fill or back)
                    end
                end
                print(back .. back .. back .. line .. back .. back .. back)
            end
        end
    end

    -- processing loop --
    if ctx.qr:isRunning() then
        doRedraw = not continuous
        if ctx.qr:genframe() then
            ctx.loopEnd = loopc
            doRedraw = true
            if lcd ~= nil then
                ctx.pxlSize = math.min(math.floor(math.min(LCD_H, LCD_H) / (ctx.qr.width + 2)))
            else
                printFrame(ctx.qr.frame, ctx.qr.width)
                print("finished with usage:", getUsage(), "loops:", loopc)
                return 1
            end
        end
        print("QR at frame", loopc, "progress", ctx.qr.progress, "load:", getUsage(), ctx.qr.isvalid and "valid" or "")
    end
    collectgarbage()
    return 0
end


if lcd == nil then
    local startTime
    function getUsage()
        return math.floor((os.clock() - startTime) * 500000)
    end
    init()
    for i = 0, 100 do
        startTime = os.clock()
        if run() == 1 then return end
        repeat until (os.clock() - startTime) > 0.01
   end
    print("end running")
end

return { init=init, run = run, background=background, qr=Qr, getGps=getGps }
