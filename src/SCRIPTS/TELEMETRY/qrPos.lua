local FILE_PATH = "/SCRIPTS/TELEMETRY"
print(_VERSION)
if getUsage == nil then --not simulator, here's regular lua
    if not bit32 ~= nil then
        print("loading bit32")
        load("bit32={band=function(a,b) return a&b end,bor=function(a,b)return a|b end,bxor=function(a,b) return a~b end,bnot=function(a) return ~a end,rshift=function(a,n) return a>>n end,lshift=function(a,n)  return a<<n end}")()
        -- loadScript(FILE_PATH .. "/test2.lua")()
    end
end

-- local qrcode = loadScript(FILE_PATH .. "/qrencode.lua", env)()
-- print("qrcode loaded ", qrcode)
-- collectgarbage()

local function shallowcopy(orig)
    local copy = {}
    for orig_key, orig_value in pairs(orig) do
        copy[orig_key] = orig_value
    end
    return copy
end

Qr = {
    strinbuf  = {},
    eccbuf    = {},
    qrframe   = {},
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
    isvalid   = false,
    progress  = 0,
    resume    = nil --continuation data store
}

function Qr:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function Qr:reset()
    self.strinbuf, self.eccbuf, self.qrframe, self.framask, self.genpoly = {}, {}, {}, {}, {}
    self.isvalid, self.progress, self.resume = false, 0, nil
end

--black to qrframe, white to mask (later black frame merged to mask)
function Qr:putalign(x, y)
    self.qrframe[x + self.width * y] = true
    for j = -2, 2 - 1 do
        self.qrframe[(x + j)     + self.width * (y - 2    )] = true;
        self.qrframe[(x - 2)     + self.width * (y + j + 1)] = true;
        self.qrframe[(x + 2)     + self.width * (y + j    )] = true;
        self.qrframe[(x + j + 1) + self.width * (y + 2    )] = true;
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

-- Galois field log table
function Qr:glogLookup(i)
    local lookup = "\255\000\001\025\0022\026\198\003\2233\238\027h\199K\004d\224\0144\141\239\129\028\193i\248\200\008Lq\005\138e/\225$\015\0335\147\142\218\240\018\130E\029\181\194}j'\249\185\201\154\009xM\228r\166\006\191\139bf\2210\253\226\152%\179\016\145\034\1366\208\148\206\143\150\219\189\241\210\019\092\1318F@\030B\182\163\195H~nk:(T\250\133\186=\202^\155\159\010\021y+N\212\229\172s\243\167W\007p\192\247\140\128c\013gJ\222\2371\197\254\024\227\165\153w&\184\180|\017D\146\217#\032\137.7?\209[\149\188\207\205\144\135\151\178\220\252\190a\242V\211\171\020*]\158\132<9SGmA\162\031-C\216\183{\164v\196\023I\236\127\012o\246l\161;R)\157U\170\251`\134\177\187\204>Z\203Y_\176\156\169\160Q\011\245\022\235zu,\215O\174\213\233\230\231\173\232t\214\244\234\168PX\175"
    i = math.max(1, i)
    return (i > #lookup) and nil or string.byte(string.sub(lookup, i, i))
end

-- Galios field exponent table
function Qr:gexpLookup(i)
    local lookup = "\001\002\004\008\016\032@\128\029:t\232\205\135\019&L\152-Z\180u\234\201\143\003\006\012\0240`\192\157'N\156%J\1485j\212\181w\238\193\159#F\140\005\010\020(P\160]\186i\210\185o\222\161_\190a\194\153/^\188e\202\137\015\030<x\240\253\231\211\187k\214\177\127\254\225\223\163[\182q\226\217\175C\134\017\034D\136\013\0264h\208\189g\206\129\031>|\248\237\199\147;v\236\197\1513f\204\133\023.\092\184m\218\169O\158\033B\132\021*T\168M\154)R\164U\170I\1469r\228\213\183s\230\209\191c\198\145?~\252\229\215\179{\246\241\255\227\219\171K\1501b\196\1497n\220\165W\174A\130\0252d\200\141\007\014\0288p\224\221\167S\166Q\162Y\178y\242\249\239\195\155+V\172E\138\009\018$H\144=z\244\245\247\243\251\235\203\139\011\022,X\176}\250\233\207\131\0276l\216\173G\142\000"
    i = math.max(1, i)
    return (i > #lookup) and nil or string.byte(string.sub(lookup, i, i))
end

-- 4 per version: number of blocks 1,2; data width; ecc width
function Qr:eccblocksLookup(i)
    -- only the first 14 lines (56 lookups)
    local lookup = "\001\000\019\007\001\000\016\010\001\000\013\013\001\000\009\017\001\000\034\010\001\000\028\016\001\000\022\022\001\000\016\028\001\0007\015\001\000,\026\002\000\017\018\002\000\013\022\001\000P\020\002\000\032\018\002\000\024\026\004\000\009\016\001\000l\026\002\000+\024\002\002\015\018\002\002\011\022\002\000D\018\004\000\027\016\004\000\019\024\004\000\015\028\002\000N\020\004\000\031\018\002\004\014\018\004\001\013\026\002\000a\024\002\002&\022\004\002\018\022\004\002\014\026\002\000t\030\003\002$\022\004\004\016\020\004\004\012\024\002\002D\018\004\001+\026\006\002\019\024\006\002\015\028\004\000Q\020\001\0042\030\004\004\022\028\003\008\012\024\002\002\092\024\006\002$\022\004\006\020\026\007\004\014\028\004\000k\026\008\001%\022\008\004\020\024\012\004\011\022"
    i = math.max(1, i) --for some reason it starts at negative numbers
    return (i > #lookup) and nil or string.byte(string.sub(lookup, i, i))
end

-- alignment pattern (used once)
function Qr:adeltaLookup(i)
    local lookup = "\000\011\015\019\023\027\031\016\018\020\022\024\026\028\020\022\024\024\026\028\028\022\024\024\026\026\028\028\024\024\026\026\026\028\028\024\026\026\026\028\028"
    i = math.max(1, i + 1)
    return (i > #lookup) and nil or string.byte(string.sub(lookup, i, i))
end

-- version block (used once)
function Qr:vpatLookup(i)
    local tbl = {
        0xc94, 0x5bc, 0xa99, 0x4d3, 0xbf6, 0x762, 0x847, 0x60d,
        0x928, 0xb78, 0x45d, 0xa17, 0x532, 0x9a6, 0x683, 0x8c9,
        0x7ec, 0xec4, 0x1e1, 0xfab, 0x08e, 0xc1a, 0x33f, 0xd75,
        0x250, 0x9d5, 0x6f0, 0x8ba, 0x79f, 0xb0b, 0x42e, 0xa64,
        0x541, 0xc69
    }
    return tbl[i + 1]
end

-- format word lookup (used once)
function Qr:fmtwordLookup(i)
    local tbl = {
        0x77c4, 0x72f3, 0x7daa, 0x789d, 0x662f, 0x6318, 0x6c41, 0x6976, --L
        0x5412, 0x5125, 0x5e7c, 0x5b4b, 0x45f9, 0x40ce, 0x4f97, 0x4aa0, --M
        0x355f, 0x3068, 0x3f31, 0x3a06, 0x24b4, 0x2183, 0x2eda, 0x2bed, --Q
        0x1689, 0x13be, 0x1ce7, 0x19d0, 0x0762, 0x0255, 0x0d0c, 0x083b  --H
    }
    return tbl[i + 1]
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

local function xorEqls(table, index, value)
    table[index] = (table[index] ~= true) and true or nil
end

-- Apply the selected mask out of the 8.
function Qr:applymask(m)
    if m == 0 then
        for y = 0, self.width - 1 do
            for x = 0, self.width - 1 do
                if bit32.band((x + y), 1) == 0 and not self:ismasked(x, y) then
                    xorEqls(self.qrframe, x + y * self.width) --^
                end
            end
        end
    elseif m == 1 then
        for y = 0, self.width - 1 do
            for x = 0, self.width - 1 do
                if bit32.band(y, 1) == 0 and not self:ismasked(x, y) then
                    xorEqls(self.qrframe, x + y * self.width) --^
                end
            end
        end
    elseif m == 2 then
        for y = 0, self.width - 1 do
            local rx = 0
            for x = 0, self.width - 1 do
                if rx == 3 then rx = 0 end
                if not rx and not self:ismasked(x, y) then
                    xorEqls(self.qrframe, x + y * self.width) --^
                end
                rx = rx + 1
            end
        end
    end
end

--Generate QR frame array
function Qr:genframe(instring)

    if self.progress == 0 then
        print("Qr: begin on " .. instring)
        self.isvalid = false
        self.progress = self.progress + 1
    end
    if self.progress == 1 then
        if self.resume == nil then self.resume = {vsn = 0} end
        -- find the smallest version that fits the string
        for vsn = self.resume.vsn, 39 do
            if getUsage() > 60 then
                self.resume.vsn = vsn
                return
            end
            local k = (self.ecclevel - 1) * 4 + (vsn - 1) * 16
            self.neccblk1 = self:eccblocksLookup(k + 1)
            k = k + 1
            self.neccblk2 = self:eccblocksLookup(k + 1)
            k = k + 1
            self.datablkw = self:eccblocksLookup(k + 1)
            k = k + 1
            self.eccblkwid = self:eccblocksLookup(k + 1)
            k = self.datablkw * (self.neccblk1 + self.neccblk2) + self.neccblk2 - 3 + (self.version <= 9 and 1 or 0)
            if #instring <= k then
                self.version = vsn
                break
            end
        end
        self.resume = nil
        self.width = 17 + 4 * self.version;
        print("QR: finished calculating version [" .. tostring(self.version) .. "] and width: " .. tostring(self.width))

        self.progress = self.progress + 1
        if (getUsage() > 50) then return end
    end

    if self.progress == 2 then
        -- allocate, clear and setup data structures
        local eccbufLen = self.datablkw + (self.datablkw + self.eccblkwid) * (self.neccblk1 + self.neccblk2) + self.neccblk2
        for t = 0, eccbufLen - 1 do
            self.eccbuf[t] = 0
        end

        -- don't pre-allocate anymore: leave sparse to use less memory
        -- for t = 0, self.width * self.width - 1 do self.qrframe[t] = 0 end
        -- for t = 0, (self.width * (self.width + 1) + 1) / 2 - 1 do self.framask[t] = nil end
        print("QR: finished allocate")

        self.progress = self.progress + 1
        if (getUsage() > 50) then return end
    end

    if self.progress == 3 then
        -- insert finders - black to frame, white to mask
        for t = 0, 2 do
            local k = 0;
            local y = 0;
            if t == 1 then k = (self.width - 7) end
            if t == 2 then y = (self.width - 7) end
            self.qrframe[(y + 3) + self.width * (k + 3)] = true
            for x = 0, 5 do
                self.qrframe[(y + x) + self.width * k]           = true
                self.qrframe[y + self.width * (k + x + 1)]       = true
                self.qrframe[(y + 6) + self.width * (k + x)]     = true
                self.qrframe[(y + x + 1) + self.width * (k + 6)] = true
            end
            for x = 1, 4 do
                self:setmask(y + x, k + 1)
                self:setmask(y + 1, k + x + 1)
                self:setmask(y + 5, k + x)
                self:setmask(y + x + 1, k + 5)
            end
            for x = 2, 3 do
                self.qrframe[(y + x) + self.width * (k + 2)]     = true
                self.qrframe[(y + 2) + self.width * (k + x + 1)] = true
                self.qrframe[(y + 4) + self.width * (k + x)]     = true
                self.qrframe[(y + x + 1) + self.width * (k + 4)] = true
            end
        end

        -- alignment blocks
        if self.version > 1 then
            local t = self:adeltaLookup(self.version)
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

        print("QR: finished alignment")
        self.progress = self.progress + 1
        if (getUsage() > 50) then return end
    end

    if self.progress == 4 then
        -- single black
        self.qrframe[8 + self.width * (self.width - 8)] = true

        -- timing gap - mask only
        for y = 0, 6 do
            self:setmask(7, y)
            self:setmask(self.width - 8, y)
            self:setmask(7, y + self.width - 7)
        end
        for x = 0, 7 do
            self:setmask(x, 7)
            self:setmask(x + self.width - 8, 7)
            self:setmask(x, self.width - 8)
        end

        -- reserve mask-format area
        for x = 0, 8 do
            self:setmask(x, 8)
        end
        for x = 0, 7 do
            self:setmask(x + self.width - 8, 8)
            self:setmask(8, x)
        end
        for y = 0, 6 do
            self:setmask(8, y + self.width - 7)
        end

        -- timing row/col
        for x = 0, self.width - 14 - 1 do
            if bit32.band(x, 1) == 1 then
                self:setmask(8 + x, 6)
                self:setmask(6, 8 + x)
            else
                self.qrframe[(8 + x) + self.width * 6] = true
                self.qrframe[6 + self.width * (8 + x)] = true
            end
        end

        -- version block
        if self.version > 6 then
            local t = self:vpatLookup(self.version - 7 - 1)
            local k = 17
            for x = 0, 5 do
                for y = 0, 2 do -- and k--
                    if bit32.band(1, (k > 11 and bit32.rshift(self.version, (k - 12)) or bit32.rshift(t, k))) == 1 then
                        self.qrframe[(5 - x) + self.width * (2 - y + self.width - 11)] = true
                        self.qrframe[(2 - y + self.width - 11) + self.width * (5 - x)] = true
                    else
                        self:setmask(5 - x, 2 - y + self.width - 11)
                        self:setmask(2 - y + self.width - 11, 5 - x)
                    end
                    k = k - 1
                end
            end
        end

        -- sync mask bits - only set above for white spaces, so add in black bits
        for y = 0, self.width - 1 do
            for x = 0, y do --inclusive
                if self.qrframe[x + self.width * y] == true then
                    self:setmask(x, y)
                end
            end
        end

        print("QR: finished basic fill")
        self.progress = self.progress + 1
        if (getUsage() > 50) then return end
    end

    if self.progress == 5 then
        -- convert string to bitstream
        -- 8 bit data to QR-coded 8 bit data (numeric or alphanum, or kanji not supported)
        local v = #instring

        -- string to array
        for i = 0, v - 1 do --we'll force lua tables to use 0-start addressing
            self.eccbuf[i] = string.byte(instring, i + 1) --adjust for 1-based lua stdlib numbering
            self.strinbuf[i] = string.byte(instring, i + 1)
        end

        -- calculate max string length
        self.maxlength = self.datablkw * (self.neccblk1 + self.neccblk2) + self.neccblk2
        if (v >= self.maxlength - 2) then
            v = self.maxlength - 2
            if (self.version > 9) then
                v = v - 1
            end
        end

        -- shift and repack to insert length prefix
        if (self.version > 9) then
            local i = v
            self.strinbuf[i + 2] = 0
            self.strinbuf[i + 3] = 0
            while i > 0 do
                i = i - 1
                local t = self.strinbuf[i]
                self.strinbuf[i + 3] = bit32.bor(self.strinbuf[i + 3], bit32.band(255, bit32.lshift(t, 4)))
                self.strinbuf[i + 2] = bit32.rshift(t, 4)
            end
            self.strinbuf[2] = bit32.bor(self.strinbuf[2], bit32.band(255, bit32.lshift(v, 4)))
            self.strinbuf[1] = bit32.rshift(v, 4)
            self.strinbuf[0] = bit32.bor(0x40, bit32.rshift(v, 12))
        else
            local i = v
            self.strinbuf[i + 1] = 0
            self.strinbuf[i + 2] = 0
            while i > 0 do
                i = i - 1
                local t = self.strinbuf[i]
                self.strinbuf[i + 2] = bit32.bor(self.strinbuf[i + 2], bit32.band(255, bit32.lshift(t, 4)))
                self.strinbuf[i + 1] = bit32.rshift(t, 4)
            end
            self.strinbuf[1] = bit32.bor(self.strinbuf[1], bit32.band(255, bit32.lshift(v, 4)))
            self.strinbuf[0] = bit32.bor(0x40, bit32.rshift(v, 4))
        end

        -- fill to end with pad pattern
        for i = v + 3 - (self.version < 10 and 1 or 0), self.maxlength - 1, 2 do
            self.strinbuf[i] = 0xec
            self.strinbuf[i + 1] = 0x11
        end
        print("QR: finished bitstream")
        self.progress = self.progress + 1
        if (getUsage() > 10) then return end
    end

    if self.progress == 6 then
        -- calculate and append ECC
        -- calculate generator polynomial
        if self.resume == nil then --first time through
            self.genpoly[0] = 1;
            self.resume = {i=0, j=0} --j for 2nd loop below
        end
        local ctx = self.resume
        for i = ctx.i, self.eccblkwid - 1 do
            ctx.i = i
            if getUsage() > 40 then return end
            self.genpoly[i + 1] = 1;
            for j = i, 1, -1 do
                self.genpoly[j] = (self.genpoly[j] >= 1) and bit32.bxor(self.genpoly[j - 1], self:gexpLookup(1 + self:modnn(self:glogLookup(1 + self.genpoly[j]) + i))) or self.genpoly[j - 1] --^
            end
            self.genpoly[0] = self:gexpLookup(1 + self:modnn(self:glogLookup(1 + self.genpoly[0]) + i))
        end
        ctx.i = ctx.i + 1 --increment once more
        for j = ctx.j, self.eccblkwid do --inclusive
            ctx.j = j
            if getUsage() > 40 then return end
            self.genpoly[j] = self:glogLookup(1 + self.genpoly[j]); -- use logs for genpoly[] to save calc step
        end
        -- don't clear context, next step wants the lookup tables
        if table ~= nil then print("QR: genpoly", table.unpack(self.genpoly)) end --desktop only
        print("QR: finished generator polynomial")
        self.progress = self.progress + 1
        if (getUsage() > 50) then return end
    end

    if self.progress == 7 then
        -- append ecc to data buffer
        if self.resume.blk == nil then
            self.resume = {blk=0, j=0, k=self.maxlength, y=0}
        end
        local ctx = self.resume
        for blk = ctx.blk, 1 do
            for j = ctx.j, (blk == 0 and self.neccblk1 or self.neccblk2) - 1 do
                -- Calculate and append ECC data to data block.  Block is in strinbuf, indexes to buffers given.
                --appendrs function, inlined:
                if ctx.id == nil then
                    for id = 0, self.eccblkwid - 1 do
                        self.strinbuf[ctx.k + id] = 0
                    end
                    ctx.id = 0
                end
                for id = ctx.id, self.datablkw + blk - 1 do
                    ctx.id = id
                    if getUsage() > 60 then return end
                    local fb = self:glogLookup(1 + bit32.bxor(self.strinbuf[ctx.y + id], self.strinbuf[ctx.k])) --^
                    if fb ~= 255 then     --fb term is non-zero
                        for jd = 1, self.eccblkwid - 1 do
                            self.strinbuf[ctx.k + jd - 1] = bit32.bxor(self.strinbuf[ctx.k + jd], self:gexpLookup(1 + self:modnn(fb + self.genpoly[self.eccblkwid - jd]))) --^
                        end
                    else
                        for jd = ctx.k, ctx.k + self.eccblkwid - 1 do
                            self.strinbuf[jd] = self.strinbuf[jd + 1]
                        end
                    end
                    self.strinbuf[ctx.k + self.eccblkwid - 1] = fb == 255 and 0 or self:gexpLookup(1 + self:modnn(fb + self.genpoly[0]))
                end
                ctx.id = nil
                ctx.y = ctx.y + self.datablkw + blk
                ctx.k = ctx.k + self.eccblkwid
                ctx.j = j
            end
            ctx.blk = blk
        end
        print("QR: finished appending ecc")
        self.resume = nil
        self.progress = self.progress + 1
        if (getUsage() > 30) then return end
    end

    if self.progress == 8 then
        -- interleave blocks
        local y = 0;
        local iback = 0
        for i = 0, self.datablkw - 1 do
            for j = 0, self.neccblk1 - 1 do
                self.eccbuf[y] = self.strinbuf[i + j * self.datablkw]
                y = y + 1
            end
            for j = 0, self.neccblk2 - 1 do
                self.eccbuf[y] = self.strinbuf[(self.neccblk1 * self.datablkw) + i + (j * (self.datablkw + 1))]
                y = y + 1
            end
            iback = i
        end
        for j = 0, self.neccblk2 - 1 do
            self.eccbuf[y] = self.strinbuf[(self.neccblk1 * self.datablkw) + iback + (j * (self.datablkw + 1))]
            y = y + 1
        end
        for i = 0, self.eccblkwid - 1 do
            for j = 0, self.neccblk1 + self.neccblk2 - 1 do
                self.eccbuf[y] = self.strinbuf[self.maxlength + i + j * self.eccblkwid]
                y = y + 1
            end
        end

        self.strinbuf = shallowcopy(self.eccbuf); --copy by value!
        print("QR: finished interleaving blocks")
        self.progress = self.progress + 1
        if (getUsage() > 50) then return end
    end

    if self.progress == 9 then
        -- pack bits into frame avoiding masked area.
        if self.resume == nil then
            self.resume = {x = self.width - 1, y = self.width - 1, v = true, k = true, i = 0}
        end
        local ctx = self.resume --shorter name..
        -- inteleaved data and ecc codes
        local m = (self.datablkw + self.eccblkwid) * (self.neccblk1 + self.neccblk2) + self.neccblk2;
        for i = self.resume.i, m - 1 do
            self.resume.i = i
            if (getUsage() > 80) then return end

            local t = self.strinbuf[i]
            for j = 0, 7 do
                if bit32.band(0x80, t) >= 1 then
                    self.qrframe[ctx.x + self.width * ctx.y] = true
                end
                while true do   -- find next fill position
                    if ctx.v then
                        ctx.x = ctx.x - 1
                    else
                        ctx.x = ctx.x + 1
                        if ctx.k then
                            if ctx.y ~= 0 then
                                ctx.y = ctx.y - 1
                            else
                                ctx.x = ctx.x - 2;
                                ctx.k = not ctx.k;
                                if ctx.x == 6 then
                                    ctx.x = ctx.x - 1
                                    ctx.y = 9;
                                end
                            end
                        else
                            if ctx.y ~= (self.width - 1) then
                                ctx.y = ctx.y + 1
                            else
                                ctx.x = ctx.x - 2
                                ctx.k = not ctx.k
                                if ctx.x == 6 then
                                    ctx.x = ctx.x - 1
                                    ctx.y = ctx.y - 8;
                                end
                            end
                        end
                    end
                    ctx.v = not ctx.v;
                    if not self:ismasked(ctx.x, ctx.y) then
                        break
                    end
                end
                t = bit32.lshift(t, 1)
            end
        end
        print("QR: finished packing")
        self.resume = nil
        self.progress = self.progress + 1
        if (getUsage() > 20) then return end
    end

    if self.progress == 10 then
        -- save pre-mask copy of frame
        self.strinbuf = {}

        -- self.strinbuf = shallowcopy(self.qrframe)
        -- self:applymask(t);
        if self.resume == nil then
            self.resume = 0
        end
        local t = 0 --TODO yes, here's method 0:
        for y = self.resume, self.width - 1 do
            self.resume = y
            if (getUsage() > 60) then return end
            for x = 0, self.width - 1 do
                if bit32.band((x + y), 1) == 0 and not self:ismasked(x, y) then
                    xorEqls(self.qrframe, x + y * self.width) --^
                end
            end
        end
        self.resume = nil
        -- x = self.badcheck(); --TODO tim

        -- add in final mask/ecclevel bytes
        local y = self:fmtwordLookup(bit32.lshift(t + (self.ecclevel - 1), 3))
        -- low byte
        for bit = 0, 7 do
            if bit32.band(y, 1) == 1 then
                self.qrframe[(self.width - 1 - bit) + self.width * 8] = true
                self.qrframe[8 + self.width * (bit + (bit < 6 and 0 or 1))] = true
            end
            y = bit32.rshift(y, 1)
        end
        -- high byte
        for bit = 0, 6 do
            if bit32.band(y, 1) == 1 then
                self.qrframe[8 + self.width * (self.width - 7 + bit)] = true
                self.qrframe[((bit >= 1) and (6 - bit) or 7) + self.width * 8] = true
            end
            y = bit32.rshift(y, 1)
        end
        print("QR: finished adding final ecc/level info")
        self.progress = 0
        local back = self.qrframe
        self:reset()
        self.qrframe = back
        self.isvalid = true
        return self.isvalid
    end
end

local loopc = 0
local qrGenerator = nil
local qr = {
    str = "", renderline = nil, frame = nil,
    loopStart = 0, loopEnd = 0, pxlSize = 2, width = 29
}
local prefixes = { "", "geo:", "comgooglemaps://?q=", "GURU://" }
local prefixIndex = 1
local clearLCD = true
local continuous = false
local continuousFrameInterval = 100
local gpsfield = getFieldInfo ~= nil and getFieldInfo("GPS") or nil

local function getGps()
    if gpsfield ~= nil then
        local gps = getValue(gpsfield.id)
        if type(gps) == "table" and gps.lat ~= nil and gps.lon ~= nil then
            return string.format("%.6f,%.6f", gps.lat, gps.lon)
        else
            return "no gps"
        end
    else
        return "no gps sensor"
    end
end

local function run(event)
    loopc = loopc + 1
    if lcd ~= nil then
        if clearLCD then
            lcd.clear()
        else
            lcd.drawFilledRectangle(0, LCD_H - 8, LCD_W, 8, ERASE)
        end
        local location = getGps()
        local newStr = prefixes[prefixIndex] .. location
        if newStr ~= qr.str and qrGenerator == nil then
            if continuous and (qrGenerator == nil) and ((loopc - qr.loopEnd) > continuousFrameInterval) then
                event = EVT_ENTER_BREAK  --easy way to start
            end
            qr.str = newStr
        end
        --TODO if contains // replace , with %2C
        local qrXoffset = math.floor((LCD_W - qr.pxlSize * (qr.width + 2)) / 2)

        lcd.drawText(0, LCD_H - 8, qr.str, SMLSIZE)
        if qrGenerator ~= nil then --draw progress counter
            lcd.drawFilledRectangle(qrXoffset, (continuous and (LCD_H - 14) or 20), qr.pxlSize * qr.width, 5, ERASE)
            lcd.drawGauge(qrXoffset, (continuous and (LCD_H - 14) or 20), qr.pxlSize * qr.width, 5, qrGenerator.progress, 10)
        end
        if qr.loopEnd ~= 0 then lcd.drawText(LCD_W, LCD_H - 8, string.format("c=%d", qr.loopEnd - qr.loopStart), SMLSIZE + RIGHT) end

        if event == EVT_ENTER_BREAK then
            if (qrGenerator == nil) then
                qrGenerator = Qr:new(nil)
            end
            qrGenerator:reset()
            qr.loopStart = loopc
        elseif event == EVT_VIRTUAL_MENU then
            continuous = not continuous
            print("continuous mode " .. (continuous and "on" or "off"))
        elseif event == EVT_EXIT_BREAK then
            clearLCD = true
        elseif event == EVT_VIRTUAL_INC then
            prefixIndex = math.min(prefixIndex + 1, #prefixes)
            clearLCD = true
        elseif event == EVT_VIRTUAL_DEC then
            prefixIndex = math.max(prefixIndex - 1, 1)
            clearLCD = true
        end
        if qr.renderline ~= nil then
            clearLCD = false
            -- lcd.drawFilledRectangle(qrXoffset, 0, qrXoffset + qr.pxlSize * qr.width, qr.pxlSize * qr.width, ERASE)
            for i = qr.renderline, qr.width - 1 do
                qr.renderline = i
                if getUsage() > 70 then return end
                for j = 0, qr.width - 1 do
                    if qr.frame[j * qr.width + i] == true then
                        lcd.drawFilledRectangle(qrXoffset + j * qr.pxlSize + qr.pxlSize, i * qr.pxlSize + qr.pxlSize, qr.pxlSize, qr.pxlSize, FORCE)
                    end
                end
            end
            print("JUST FINISHED rendering") --only reached if for loop completes
            qr.renderline = nil
            qr.frame = nil
        end
    end

    if lcd == nil then --desktop mode!
        if loopc > 100 then return 1 end --limit total looping in case there's a bug
        if qrGenerator == nil then
            qrGenerator = Qr:new(nil)
            qr.str = arg[1] or "hello world"
        end
        function printFrame(buffer, width, back, fill)
            back = back or "  "
            fill = fill or "##"
            for i = -3, width + 2 do
                local line = ""
                for j = 0, width - 1 do
                    if i < 0 or i >= width then
                        line = line .. back
                    else
                        line = line .. ((buffer[j * width + i] == true) and fill or back)
                    end
                end
                print(i, back .. back .. back .. line .. back .. back .. back)
            end
        end
    end

    -- processing loop --
    if qrGenerator ~= nil then
        clearLCD = not continuous
        if qrGenerator:genframe(qr.str) then
            qr.renderline = 0
            qr.loopEnd = loopc
            qr.frame = qrGenerator.qrframe --save the qr table, perhaps in future minimize it first
            qr.width = qrGenerator.width
            qrGenerator = nil --save memory!
            clearLCD = true
            print("JUST FINISHED QR")
            if lcd ~= nil then
                qr.pxlSize = math.min(math.floor(math.min(LCD_H, LCD_H) / (qr.width + 2))) --calculate QR pixel size
            else
                printFrame(qr.frame, qr.width)
                print("finished with usage:", getUsage(), "loops:", loopc)
                return 1 --ends desktop script
            end
        end
        print("QR at frame", loopc, "progress", qr.progress, "load:", getUsage(), qr.isvalid and "valid" or "")
    end
    collectgarbage()
    return 0
end


if lcd == nil then
    local startTime
    function getUsage()
        return math.floor((os.clock() - startTime) * 500000)
    end
    print("defined getUsage")
    for i = 0, 100 do
        startTime = os.clock()
        if run() == 1 then return end
        repeat until (os.clock() - startTime) > 0.01
   end
    print("end running")
end

return { run = run }
