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
local FMTWORD_LOOKUP = "\119\196\114\243\125\170\120\157\102\047\099\024\108\065\105\118\084\018\081\037\094\124\091\075\069\249\064\206\079\151\074\160\053\095\048\104\063\049\058\006\036\180\033\131\046\218\043\237\022\137\019\190\028\231\025\208\007\098\002\085\013\012\008\059"
local function getFmtWord(index)
    local pos = index * 2 + 1
    return bit32.bor(bit32.lshift(string.byte(FMTWORD_LOOKUP, pos), 8), string.byte(FMTWORD_LOOKUP, pos + 1))
end

local MAX_QR_VERSION = 4  -- Version 4 = 33x33, sufficient for GPS with any prefix
local MAX_LOAD = 40  -- Max CPU load percentage before yielding/differing
local COUNT_PER_SEC = 20 --opentx seems to run at 20hz

Qr = {
    eccbuf    = nil,
    frame     = nil,
    framask   = nil, --is masked lookup
    genpoly   = nil,
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
    resume    = nil, --continuation data store
    bmpPath   = nil,
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
    self.eccbuf, self.framask, self.genpoly = nil, nil, nil
    self.isvalid, self.progress, self.resume = false, nil, nil
    if partial == nil then
        self.frame, self.width = nil, 0
    end
end

--black to qrframe, white to mask (later black frame merged to mask)
function Qr:putalign(x, y)
    self:setFrame(x + self.width * y)
    for j = -2, 2 - 1 do
        self:setFrame((x + j)     + self.width * (y - 2    ))
        self:setFrame((x - 2)     + self.width * (y + j + 1))
        self:setFrame((x + 2)     + self.width * (y + j    ))
        self:setFrame((x + j + 1) + self.width * (y + 2    ))
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
    if x > y then x, y = y, x end
    local bt = bit32.rshift((y * y) + y, 1) + x
    --now save this as bitpacked:
    local word = bit32.rshift(bt, 5)  -- bt / 32
    local bit = bit32.band(bt, 31)     -- bt % 32
    self.framask[word] = bit32.bor(self.framask[word] or 0, bit32.lshift(1, bit))
end

-- check mask - since symmetrical use half
function Qr:ismasked(x, y)
    if x > y then x, y = y, x end
    local bt = bit32.rshift((y * y) + y, 1) + x
    --now use bitpacked read:
    local word = bit32.rshift(bt, 5)  -- bt / 32
    local bit = bit32.band(bt, 31)     -- bt % 32
    return bit32.band(self.framask[word] or 0, bit32.lshift(1, bit)) ~= 0
end

-- bit packed frame set/get
function Qr:setFrame(idx, boolval)
    if boolval == nil then boolval = true end  -- Default to true
    local word = bit32.rshift(idx, 5)  -- idx / 32
    local bit = bit32.band(idx, 31)     -- idx % 32
    if boolval then
        self.frame[word] = bit32.bor(self.frame[word] or 0, bit32.lshift(1, bit))
    else
        self.frame[word] = bit32.band(self.frame[word] or 0, bit32.bnot(bit32.lshift(1, bit)))
    end
end
function Qr:getFrame(idx)
    local word = bit32.rshift(idx, 5)
    local bit = bit32.band(idx, 31)
    return bit32.band(self.frame[word] or 0, bit32.lshift(1, bit)) ~= 0
end

--Generate QR frame array
function Qr:genframe()
    if self.progress == 0 then
        self.progress = 1
    end

    if self.progress == 1 then --determine version
        if self.resume == nil then self.resume = 0 end
        for vsn = self.resume, MAX_QR_VERSION do
            if getUsage() > MAX_LOAD and vsn > self.resume then
                self.resume = vsn
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
        if getUsage() > MAX_LOAD then return end
    end

    if self.progress == 2 then --initialize frame and eccbuf
        local eccbufLen = self.datablkw + (self.datablkw + self.eccblkwid) * (self.neccblk1 + self.neccblk2) + self.neccblk2
        self.eccbuf = {}
        for t = 0, eccbufLen - 1 do
            self.eccbuf[t] = 0
        end
        self.progress = 3
        if getUsage() > MAX_LOAD then return end
    end

    if self.progress == 3 then --insert finder patterns and alignment blocks
        -- insert finders - black to frame, white to mask
        self.framask = {}
        local maxMaskIdx = bit32.rshift(self.width * (self.width + 1), 1)
        local maskWords = math.ceil(maxMaskIdx / 32)
        for i = 0, maskWords - 1 do self.framask[i] = 0 end --init bitpacked array
        self.frame = {}
        local numWords = math.ceil(self.width * self.width / 32) -- bitpacked words
        for i = 0, numWords - 1 do self.frame[i] = 0 end -- init bitpacked frame array

        for t = 0, 2 do
            local k, y = 0, 0
            if t == 1 then k = self.width - 7 end
            if t == 2 then y = self.width - 7 end
            self:setFrame((y + 3) + self.width * (k + 3))
            for x = 0, 5 do
                self:setFrame((y + x) + self.width * k)
                self:setFrame(y + self.width * (k + x + 1))
                self:setFrame((y + 6) + self.width * (k + x))
                self:setFrame((y + x + 1) + self.width * (k + 6))
            end
            for x = 1, 4 do
                self:setmask(y + x, k + 1)
                self:setmask(y + 1, k + x + 1)
                self:setmask(y + 5, k + x)
                self:setmask(y + x + 1, k + 5)
            end
            for x = 2, 3 do
                self:setFrame((y + x) + self.width * (k + 2))
                self:setFrame((y + 2) + self.width * (k + x + 1))
                self:setFrame((y + 4) + self.width * (k + x))
                self:setFrame((y + x + 1) + self.width * (k + 4))
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
        if getUsage() > MAX_LOAD then return end
    end

    if self.progress == 4 then --add timing patterns and reserve format area
        if self.resume == nil then
            self:setFrame(8 + self.width * (self.width - 8))
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
                self:setFrame(8 + x + self.width * 6)
                self:setFrame(6 + self.width * (8 + x))
            end
            self.resume = 0
        end
        -- sync mask bits
        for y = self.resume, self.width - 1 do
            if getUsage() > MAX_LOAD and y > self.resume then
                self.resume = y
                return
            end
            for x = 0, y do
                if self:getFrame(x + self.width * y) == true then
                    self:setmask(x, y)
                end
            end
        end
        self.resume = nil
        self.progress = 5
        if getUsage() > MAX_LOAD then return end
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
        if getUsage() > MAX_LOAD then return end
    end

    if self.progress == 6 then --generate ECC
        if self.resume == nil then
            self.genpoly = {}
            self.genpoly[0] = 1
            self.resume = 0
        end
        for i = self.resume, self.eccblkwid - 1 do
            if getUsage() > MAX_LOAD and i > self.resume then
                self.resume = i
                return
            end
            self.genpoly[i + 1] = 1
            for j = i, 1, -1 do
                if (self.genpoly[j]) >= 1 then
                    local glog_val = string.byte(GLOG_LOOKUP, 1 + self.genpoly[j])
                    local gexp_val = string.byte(GEXP_LOOKUP, 1 + self:modnn(glog_val + i))
                    self.genpoly[j] = bit32.bxor(self.genpoly[j - 1], gexp_val)
                else
                    self.genpoly[j] = self.genpoly[j - 1]
                end
            end
            local glog_val = string.byte(GLOG_LOOKUP, math.max(1, 1 + (self.genpoly[0])))
            self.genpoly[0] = string.byte(GEXP_LOOKUP, math.max(1, 1 + self:modnn(glog_val + i)))
        end
        for j = 0, self.eccblkwid do
            self.genpoly[j] = string.byte(GLOG_LOOKUP, math.max(1, 1 + (self.genpoly[j])))
        end
        self.resume = nil
        self.progress = 7
        collectgarbage()
        if getUsage() > MAX_LOAD then return end
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
                    if getUsage() > MAX_LOAD then return end
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
        if getUsage() > MAX_LOAD then return end
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
        if getUsage() > MAX_LOAD then return end
    end

    if self.progress == 9 then --pack bits into frame avoiding masked area
        if self.resume == nil then
            self.resume = {x = self.width - 1, y = self.width - 1, v = true, k = true, i = 0}
        end
        local tmp = self.resume
        local m = (self.datablkw + self.eccblkwid) * (self.neccblk1 + self.neccblk2) + self.neccblk2
        for i = tmp.i, m - 1 do
            tmp.i = i
            if getUsage() > MAX_LOAD then return end
            local t = self.eccbuf[i]
            for j = 0, 7 do
                if bit32.band(0x80, t) >= 1 then
                    self:setFrame(tmp.x + self.width * tmp.y)
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
        if getUsage() > MAX_LOAD then return end
    end

    if self.progress == 10 then --apply mask pattern
        collectgarbage()
        if self.resume == nil then self.resume = 0 end
        for y = self.resume, self.width - 1 do
            if getUsage() > MAX_LOAD and y > self.resume then
                self.resume = y
                return
            end
            for x = 0, self.width - 1 do
                if bit32.band((x + y), 1) == 0 and not self:ismasked(x, y) then
                    local idx = x + y * self.width
                    self:setFrame(idx, not self:getFrame(idx))
                end
            end
        end
        self.framask = nil
        collectgarbage()
        self.resume = nil
        -- add in final mask/ecclevel bytes
        local y = getFmtWord(bit32.lshift(0 + (self.ecclevel - 1), 3))
        for bit = 0, 7 do
            if bit32.band(y, 1) == 1 then
                self:setFrame((self.width - 1 - bit) + self.width * 8)
                self:setFrame(8 + self.width * (bit + (bit < 6 and 0 or 1)))
            end
            y = bit32.rshift(y, 1)
        end
        for bit = 0, 6 do
            if bit32.band(y, 1) == 1 then
                self:setFrame(8 + self.width * (self.width - 7 + bit))
                self:setFrame(((bit >= 1) and (6 - bit) or 7) + self.width * 8)
            end
            y = bit32.rshift(y, 1)
        end
        self:reset(true) --partial reset, don't reset frame & width
        self.progress = 11
        collectgarbage()
        if getUsage() > MAX_LOAD then return end
    end
    if self.progress == 11 then --apply mask pattern
        if lcd == nil and self.bmpPath == nil then --desktop luac
            self.bmpPath = "qr_temp.bmp"
        end
        if self.bmpPath ~= nil then
            self.resume = self:toBMP(self.bmpPath, self.resume, self.fgColor, self.bgColor, self.bgTransp)
            if self.resume ~= nil then --not finished
                return --keep going next loop
            end
        end
        self:reset(true) --partial reset, don't reset frame & width
        self.isvalid = true
        collectgarbage()
        return self.isvalid
    end
end

local function colorToRGB(color)
    if type(color) == "table" and #color == 3 then return color
    elseif color and bit32.band(color, 0x8000) ~= 0 then -- has RGB_FLAG
        color = bit32.rshift(color, 16) --convert 16 bit leftover color
        return {  bit32.lshift(bit32.band(bit32.rshift(color, 11), 0x1F), 3), bit32.lshift(bit32.band(bit32.rshift(color, 5), 0x3F), 2), bit32.lshift(bit32.band(color, 0x1F), 3) }
    end
end

function Qr:toBMP(filepath, resumeIdx, fgColor, bgColor, bgTransp)
    fgColor = colorToRGB(fgColor) or {0, 0, 0}
    bgColor = colorToRGB(bgColor) or {255, 255, 255}
    bgTransp = math.floor((bgTransp or 50) * 255 / 100) --0-100 mapped to 0-255
    local qrW = self.width
    local w = qrW + 2
    local rowBytes = w * 4  -- 4 bytes per pixel (32-bit BGRA)
    local rowPadding = (4 - (rowBytes % 4)) % 4
    local imageSize = (rowBytes + rowPadding) * w
    local fileSize = 54 + imageSize
    local f = io.open(filepath, resumeIdx == nil and "wb" or "ab")
    if not f then return false end

    local function writeData(data)
        if lcd ~= nil then io.write(f, data) else f:write(data) end
    end

    if resumeIdx == nil then
        local function u16(n) return string.char(n % 256, math.floor(n / 256)) end
        local function u32(n) return string.char(n % 256, math.floor(n / 256) % 256, math.floor(n / 65536) % 256, math.floor(n / 16777216)) end
        writeData("BM" .. u32(fileSize) .. u32(0) .. u32(54) ..
                  u32(40) .. u32(w) .. u32(w) .. u16(1) .. u16(32) ..
                  u32(0) .. u32(imageSize) .. u32(2835) .. u32(2835) .. u32(0) .. u32(0))
        resumeIdx = w - 1
    end

    local padding = string.rep("\000", rowPadding)
    for y = resumeIdx, 0, -1 do
        if getUsage() > MAX_LOAD then io.close(f) return y end
        local rowData = ""
        for x = 0, w - 1 do
            local isQr = x > 0 and x < w - 1 and y > 0 and y < w - 1 and self:getFrame((x - 1) + (y - 1) * qrW)
            local color = (isQr and fgColor) or bgColor
            rowData = rowData .. string.char(color[3], color[2], color[1], isQr and 255 or bgTransp)
        end
        writeData(rowData .. padding)
    end
    io.close(f)
    return nil
end

function Qr:draw(x, y, pxlSize, bgFlags, fgFlags, resumeIdx)
    if lcd == nil then return nil end
    pxlSize = pxlSize or 2
    resumeIdx = resumeIdx or 0
    if resumeIdx == 0 then
        lcd.drawFilledRectangle(x, y, (self.width + 2) * pxlSize, (self.width + 2) * pxlSize, bgFlags or ERASE)
    end
    for idx = resumeIdx, self.width * self.width - 1 do
        if (idx % 20 == 0) and getUsage() > MAX_LOAD and (idx > resumeIdx) then
            return idx -- return current index to resume later
        end
        if self:getFrame(idx) then
            local px = idx % self.width
            local py = math.floor(idx / self.width)
            lcd.drawFilledRectangle(x + px * pxlSize + pxlSize, y + py * pxlSize + pxlSize, pxlSize, pxlSize, fgFlags or CUSTOM_COLOR)
        end
    end
    return nil -- completed
end

local loopc = 0
local ctx = {
    qrStartTime = 0,
    lastValidGps = nil,
    qr = nil,
    drawIdx = nil,
    activeGps = nil,
}
local linkLabels   = { "plain", "native", "google",              "CoMaps",       "Guru" }
local linkPrefixes = { "",      "geo:",   "comgooglemaps://?q=", "cm://map?ll=", "GURU://" }
local prefixIndex = 2
local doRedraw = true
local continuous = false
local AUTO_MODE_INTERVAL = 10 --seconds
local gpsfield = nil
local lastBGloopc = 0
local LINEH = 8

local function getGps()
    if gpsfield == nil then
        gpsfield = getFieldInfo("GPS")
    end
    local gps = gpsfield and getValue(gpsfield.id) or nil
    if type(gps) == "table" and gps.lat ~= nil and gps.lon ~= nil then
        return { lat = gps.lat, lon = gps.lon, valid = true, time = getTime() }
    elseif gpsfield == nil then
        return nil --gps sensor not set up
    else
        return { lat = 0, lon = 0, valid = false }
    end
end

function truncateStr(str, maxLen)
    if #str > maxLen then
        return string.sub(str, 1, maxLen - 2) .. ".."
    else
        return str
    end
end
function clearQr()
    ctx.qr:reset()
    ctx.qrStartTime = 0
    ctx.activeGps = nil
    doRedraw = true
end

local function init()
    ctx.qr = Qr:new() --creates instance from prototype
    Qr = nil --delete prototype
    if lcd then
        ctx.qrArea = math.floor(LCD_W / 2)  -- Left half for QR
        ctx.statusX = ctx.qrArea + 1  -- Status area starts after QR

        if lcd.sizeText then
            LINEH = select(2, lcd.sizeText("Test", SMLSIZE))
            print("qr: working sizeText line height:", LINEH)
        end
    end
end

local function background() --called when script isn't being shown
    if lastBGloopc == loopc and not doRedraw then
        doRedraw = true
    end
    local location = getGps()
    if location ~= nil and location.valid then --only update when valid data retrieved
        ctx.lastValidGps = location --allows model to crash and preserve last known good
    end
    lastBGloopc = loopc
end

local function run(event)
    loopc = loopc + 1
    if lcd ~= nil then
        local doNewQr = false

        -- handle events --
        if event == EVT_ENTER_BREAK then
            doNewQr = true
        elseif event == EVT_VIRTUAL_MENU or event == EVT_ENTER_LONG then
            continuous = not continuous
            clearQr()
        elseif event == EVT_EXIT_BREAK then
            doRedraw = true
        elseif event == EVT_VIRTUAL_INC and (prefixIndex < #linkPrefixes) then
            prefixIndex = prefixIndex + 1
            clearQr()
        elseif event == EVT_VIRTUAL_DEC and (prefixIndex > 1) then
            prefixIndex = prefixIndex - 1
            clearQr()
        end

        -- update data values --
        local gpsData = getGps()
        if gpsData ~= nil and gpsData.valid then
            ctx.lastValidGps = gpsData --allows model to crash and preserve last known good
        end
        local newQrStr = linkPrefixes[prefixIndex] .. (ctx.lastValidGps and string.format("%.6f,%.6f", ctx.lastValidGps.lat, ctx.lastValidGps.lon) or "no gps")
        if continuous and (not ctx.qr.isvalid or (newQrStr ~= ctx.qr.inputstr)) and (not ctx.qr:isRunning()) and (getTime() - ctx.qrStartTime)/100 > AUTO_MODE_INTERVAL then
            doNewQr = true --start auto update
        end
        if doNewQr then
            ctx.qr:start(newQrStr)
            ctx.qrStartTime, ctx.activeGps = getTime(), ctx.lastValidGps --capture time of request and point used (includes time)
        end

        -- draw screen --
        if (doRedraw and ctx.drawIdx == nil) or ctx.qr:isRunning() then
            lcd.clear()
        else
            lcd.drawFilledRectangle(ctx.qrArea, 0, LCD_W - ctx.qrArea, LCD_H, COLOR_THEME_PRIMARY2 or ERASE)
        end

        if ctx.qr:isRunning() then
            lcd.drawText(ctx.qrArea / 2, LCD_H / 2 - 10, "Generating", SMLSIZE + CENTER)
            lcd.drawGauge(10, LCD_H / 2, ctx.qrArea - 20, 5, ctx.qr.progress, 11)
        elseif ctx.qr.isvalid and (doRedraw or ctx.drawIdx ~= nil) then
            local pxlSize = math.min(math.floor(ctx.qrArea / (ctx.qr.width + 2)), math.floor(LCD_H / (ctx.qr.width + 2)))
            local qrXoffset = math.floor((ctx.qrArea - pxlSize * (ctx.qr.width + 2)) / 2)
            local qrYoffset = math.floor((LCD_H - pxlSize * (ctx.qr.width + 2)) / 2)
            ctx.drawIdx = ctx.qr:draw(qrXoffset, qrYoffset, pxlSize, nil, nil, ctx.drawIdx)
        elseif doRedraw and not continuous then
            lcd.drawLine(ctx.qrArea - 2, 0, ctx.qrArea - 2, LCD_H, SOLID, FORCE)
            lcd.drawText(ctx.qrArea / 2, 2, "QRious Lua", SMLSIZE + CENTER)
            lcd.drawText(ctx.qrArea / 2, 2 + LINEH, "by t413", SMLSIZE + CENTER)
            lcd.drawText(ctx.qrArea / 2, LCD_H / 2 - LINEH/2, "Press ENTER", SMLSIZE + CENTER)
            lcd.drawText(ctx.qrArea / 2, LCD_H / 2 + LINEH/2, "to generate", SMLSIZE + CENTER)
        end

        -- Draw status area (right half)
        local lineY = 22 --starting y
        if not ctx.lastValidGps then
            lcd.drawText(ctx.statusX, lineY, "NOT SET UP", SMLSIZE)
        elseif not ctx.lastValidGps.valid then
            lcd.drawText(ctx.statusX, lineY, "NO FIX", SMLSIZE)
        else --valid gps
            lineY = 2 --reset to top
            lcd.drawText(ctx.statusX, lineY, string.format("%.6f", ctx.lastValidGps.lat), SMLSIZE)
            lineY = lineY + LINEH
            lcd.drawText(ctx.statusX, lineY, string.format("%.6f", ctx.lastValidGps.lon), SMLSIZE)
        end
        lineY = lineY + LINEH + 2
        lcd.drawText(ctx.statusX, lineY, linkLabels[prefixIndex] .. " link", SMLSIZE) -- Link Type
        lineY = lineY + LINEH
        local gps_src = ctx.activeGps or ctx.lastValidGps
        local dt = gps_src and gps_src.valid and (getTime() - gps_src.time) / 100 or nil
        if dt and dt > 5 then
            lcd.drawText(ctx.statusX, lineY, string.format("%ds old", dt), SMLSIZE)
            lineY = lineY + LINEH
        end
        lcd.drawText(ctx.statusX, LCD_H - LINEH, (continuous and "Auto" or "Manual") .. " mode", SMLSIZE) -- Mode, bottom aligned

        doRedraw = false
    end

    if lcd == nil then --desktop mode!
        if loopc > 100 then return 1 end --limit total looping in case there's a bug
        if ctx.qr.progress == nil then
            ctx.qr:start(arg[1] or "hello world")
        end
        function printFrame(qr, back, fill)
            back, fill = back or "  ", fill or "##"
            local pad = back:rep(3)
            for i = -2, qr.width + 1 do
            local line = {}
            for j = 0, qr.width - 1 do
                line[#line + 1] = (i < 0 or i >= qr.width) and back or (qr:getFrame(j + i * qr.width) and fill or back)
            end
            print(pad .. table.concat(line) .. pad)
            end
        end
    end

    -- processing loop --
    if ctx.qr:isRunning() then
        doRedraw = not continuous
        if ctx.qr:genframe() then -- completed!
            doRedraw = true
            if lcd ~= nil then
            else
                printFrame(ctx.qr)
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
    local argIndex = 1  -- Track which argument we're processing
    function getUsage()
        return math.floor((os.clock() - startTime) * 500000)
    end
    init()
    while argIndex <= #arg do -- Process each command line argument
        local inputStr = arg[argIndex]
        print(string.format("\n=== Generating QR #%d: '%s' ===", argIndex, inputStr))
        ctx.qr:start(inputStr)
        loopc = 0
        for i = 0, 100 do -- Run until this QR completes
            startTime = os.clock()
            if run() == 1 then break end
            repeat until (os.clock() - startTime) > 0.01
        end
        argIndex = argIndex + 1
    end
end

return {
    init=init, run = run, background=background, qr=Qr, getGps=getGps,
    linkLabels=linkLabels, linkPrefixes=linkPrefixes
}
