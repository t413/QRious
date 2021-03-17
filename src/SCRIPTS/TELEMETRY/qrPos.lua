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
    strinbuf = {},
    eccbuf   = {},
    qrframe  = {},
    framask  = {}, --is masked lookup
    rlens    = {},
    genpoly  = {},
    ecclevel=1,
    version=0,
    width=0,
    neccblk1  =0,
    neccblk2  =0,
    datablkw  =0,
    eccblkwid =0,
    maxlength = nil,
    progress  =0,
    resume = nil --continuation data store
}

function Qr:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

--black to qrframe, white to mask (later black frame merged to mask)
function Qr:putalign(x, y)
    self.qrframe[x + self.width * y] = 1
    for j = -2, 2 - 1 do
        self.qrframe[(x + j)     + self.width * (y - 2    )] = 1;
        self.qrframe[(x - 2)     + self.width * (y + j + 1)] = 1;
        self.qrframe[(x + 2)     + self.width * (y + j    )] = 1;
        self.qrframe[(x + j + 1) + self.width * (y + 2    )] = 1;
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
    local tbl = {
        0xff, 0x00, 0x01, 0x19, 0x02, 0x32, 0x1a, 0xc6, 0x03, 0xdf, 0x33, 0xee, 0x1b, 0x68, 0xc7, 0x4b,
        0x04, 0x64, 0xe0, 0x0e, 0x34, 0x8d, 0xef, 0x81, 0x1c, 0xc1, 0x69, 0xf8, 0xc8, 0x08, 0x4c, 0x71,
        0x05, 0x8a, 0x65, 0x2f, 0xe1, 0x24, 0x0f, 0x21, 0x35, 0x93, 0x8e, 0xda, 0xf0, 0x12, 0x82, 0x45,
        0x1d, 0xb5, 0xc2, 0x7d, 0x6a, 0x27, 0xf9, 0xb9, 0xc9, 0x9a, 0x09, 0x78, 0x4d, 0xe4, 0x72, 0xa6,
        0x06, 0xbf, 0x8b, 0x62, 0x66, 0xdd, 0x30, 0xfd, 0xe2, 0x98, 0x25, 0xb3, 0x10, 0x91, 0x22, 0x88,
        0x36, 0xd0, 0x94, 0xce, 0x8f, 0x96, 0xdb, 0xbd, 0xf1, 0xd2, 0x13, 0x5c, 0x83, 0x38, 0x46, 0x40,
        0x1e, 0x42, 0xb6, 0xa3, 0xc3, 0x48, 0x7e, 0x6e, 0x6b, 0x3a, 0x28, 0x54, 0xfa, 0x85, 0xba, 0x3d,
        0xca, 0x5e, 0x9b, 0x9f, 0x0a, 0x15, 0x79, 0x2b, 0x4e, 0xd4, 0xe5, 0xac, 0x73, 0xf3, 0xa7, 0x57,
        0x07, 0x70, 0xc0, 0xf7, 0x8c, 0x80, 0x63, 0x0d, 0x67, 0x4a, 0xde, 0xed, 0x31, 0xc5, 0xfe, 0x18,
        0xe3, 0xa5, 0x99, 0x77, 0x26, 0xb8, 0xb4, 0x7c, 0x11, 0x44, 0x92, 0xd9, 0x23, 0x20, 0x89, 0x2e,
        0x37, 0x3f, 0xd1, 0x5b, 0x95, 0xbc, 0xcf, 0xcd, 0x90, 0x87, 0x97, 0xb2, 0xdc, 0xfc, 0xbe, 0x61,
        0xf2, 0x56, 0xd3, 0xab, 0x14, 0x2a, 0x5d, 0x9e, 0x84, 0x3c, 0x39, 0x53, 0x47, 0x6d, 0x41, 0xa2,
        0x1f, 0x2d, 0x43, 0xd8, 0xb7, 0x7b, 0xa4, 0x76, 0xc4, 0x17, 0x49, 0xec, 0x7f, 0x0c, 0x6f, 0xf6,
        0x6c, 0xa1, 0x3b, 0x52, 0x29, 0x9d, 0x55, 0xaa, 0xfb, 0x60, 0x86, 0xb1, 0xbb, 0xcc, 0x3e, 0x5a,
        0xcb, 0x59, 0x5f, 0xb0, 0x9c, 0xa9, 0xa0, 0x51, 0x0b, 0xf5, 0x16, 0xeb, 0x7a, 0x75, 0x2c, 0xd7,
        0x4f, 0xae, 0xd5, 0xe9, 0xe6, 0xe7, 0xad, 0xe8, 0x74, 0xd6, 0xf4, 0xea, 0xa8, 0x50, 0x58, 0xaf
    }
    return tbl[i + 1]
end

-- Galios field exponent table
function Qr:gexpLookup(i)
    local tbl = {
        0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1d, 0x3a, 0x74, 0xe8, 0xcd, 0x87, 0x13, 0x26,
        0x4c, 0x98, 0x2d, 0x5a, 0xb4, 0x75, 0xea, 0xc9, 0x8f, 0x03, 0x06, 0x0c, 0x18, 0x30, 0x60, 0xc0,
        0x9d, 0x27, 0x4e, 0x9c, 0x25, 0x4a, 0x94, 0x35, 0x6a, 0xd4, 0xb5, 0x77, 0xee, 0xc1, 0x9f, 0x23,
        0x46, 0x8c, 0x05, 0x0a, 0x14, 0x28, 0x50, 0xa0, 0x5d, 0xba, 0x69, 0xd2, 0xb9, 0x6f, 0xde, 0xa1,
        0x5f, 0xbe, 0x61, 0xc2, 0x99, 0x2f, 0x5e, 0xbc, 0x65, 0xca, 0x89, 0x0f, 0x1e, 0x3c, 0x78, 0xf0,
        0xfd, 0xe7, 0xd3, 0xbb, 0x6b, 0xd6, 0xb1, 0x7f, 0xfe, 0xe1, 0xdf, 0xa3, 0x5b, 0xb6, 0x71, 0xe2,
        0xd9, 0xaf, 0x43, 0x86, 0x11, 0x22, 0x44, 0x88, 0x0d, 0x1a, 0x34, 0x68, 0xd0, 0xbd, 0x67, 0xce,
        0x81, 0x1f, 0x3e, 0x7c, 0xf8, 0xed, 0xc7, 0x93, 0x3b, 0x76, 0xec, 0xc5, 0x97, 0x33, 0x66, 0xcc,
        0x85, 0x17, 0x2e, 0x5c, 0xb8, 0x6d, 0xda, 0xa9, 0x4f, 0x9e, 0x21, 0x42, 0x84, 0x15, 0x2a, 0x54,
        0xa8, 0x4d, 0x9a, 0x29, 0x52, 0xa4, 0x55, 0xaa, 0x49, 0x92, 0x39, 0x72, 0xe4, 0xd5, 0xb7, 0x73,
        0xe6, 0xd1, 0xbf, 0x63, 0xc6, 0x91, 0x3f, 0x7e, 0xfc, 0xe5, 0xd7, 0xb3, 0x7b, 0xf6, 0xf1, 0xff,
        0xe3, 0xdb, 0xab, 0x4b, 0x96, 0x31, 0x62, 0xc4, 0x95, 0x37, 0x6e, 0xdc, 0xa5, 0x57, 0xae, 0x41,
        0x82, 0x19, 0x32, 0x64, 0xc8, 0x8d, 0x07, 0x0e, 0x1c, 0x38, 0x70, 0xe0, 0xdd, 0xa7, 0x53, 0xa6,
        0x51, 0xa2, 0x59, 0xb2, 0x79, 0xf2, 0xf9, 0xef, 0xc3, 0x9b, 0x2b, 0x56, 0xac, 0x45, 0x8a, 0x09,
        0x12, 0x24, 0x48, 0x90, 0x3d, 0x7a, 0xf4, 0xf5, 0xf7, 0xf3, 0xfb, 0xeb, 0xcb, 0x8b, 0x0b, 0x16,
        0x2c, 0x58, 0xb0, 0x7d, 0xfa, 0xe9, 0xcf, 0x83, 0x1b, 0x36, 0x6c, 0xd8, 0xad, 0x47, 0x8e, 0x00
    }
    return tbl[i + 1]
end

-- 4 per version: number of blocks 1,2; data width; ecc width
function Qr:eccblocksLookup(i)
    local tbl = {
        1, 0, 19, 7, 1, 0, 16, 10, 1, 0, 13, 13, 1, 0, 9, 17,
        1, 0, 34, 10, 1, 0, 28, 16, 1, 0, 22, 22, 1, 0, 16, 28,
        1, 0, 55, 15, 1, 0, 44, 26, 2, 0, 17, 18, 2, 0, 13, 22,
        1, 0, 80, 20, 2, 0, 32, 18, 2, 0, 24, 26, 4, 0, 9, 16,
        1, 0, 108, 26, 2, 0, 43, 24, 2, 2, 15, 18, 2, 2, 11, 22,
        2, 0, 68, 18, 4, 0, 27, 16, 4, 0, 19, 24, 4, 0, 15, 28,
        2, 0, 78, 20, 4, 0, 31, 18, 2, 4, 14, 18, 4, 1, 13, 26,
        2, 0, 97, 24, 2, 2, 38, 22, 4, 2, 18, 22, 4, 2, 14, 26,
        2, 0, 116, 30, 3, 2, 36, 22, 4, 4, 16, 20, 4, 4, 12, 24,
        2, 2, 68, 18, 4, 1, 43, 26, 6, 2, 19, 24, 6, 2, 15, 28,
        4, 0, 81, 20, 1, 4, 50, 30, 4, 4, 22, 28, 3, 8, 12, 24,
        2, 2, 92, 24, 6, 2, 36, 22, 4, 6, 20, 26, 7, 4, 14, 28,
        4, 0, 107, 26, 8, 1, 37, 22, 8, 4, 20, 24, 12, 4, 11, 22,
        3, 1, 115, 30, 4, 5, 40, 24, 11, 5, 16, 20, 11, 5, 12, 24,
        5, 1, 87, 22, 5, 5, 41, 24, 5, 7, 24, 30, 11, 7, 12, 24,
        5, 1, 98, 24, 7, 3, 45, 28, 15, 2, 19, 24, 3, 13, 15, 30,
        1, 5, 107, 28, 10, 1, 46, 28, 1, 15, 22, 28, 2, 17, 14, 28,
        5, 1, 120, 30, 9, 4, 43, 26, 17, 1, 22, 28, 2, 19, 14, 28,
        3, 4, 113, 28, 3, 11, 44, 26, 17, 4, 21, 26, 9, 16, 13, 26,
        3, 5, 107, 28, 3, 13, 41, 26, 15, 5, 24, 30, 15, 10, 15, 28,
        4, 4, 116, 28, 17, 0, 42, 26, 17, 6, 22, 28, 19, 6, 16, 30,
        2, 7, 111, 28, 17, 0, 46, 28, 7, 16, 24, 30, 34, 0, 13, 24,
        4, 5, 121, 30, 4, 14, 47, 28, 11, 14, 24, 30, 16, 14, 15, 30,
        6, 4, 117, 30, 6, 14, 45, 28, 11, 16, 24, 30, 30, 2, 16, 30,
        8, 4, 106, 26, 8, 13, 47, 28, 7, 22, 24, 30, 22, 13, 15, 30,
        10, 2, 114, 28, 19, 4, 46, 28, 28, 6, 22, 28, 33, 4, 16, 30,
        8, 4, 122, 30, 22, 3, 45, 28, 8, 26, 23, 30, 12, 28, 15, 30,
        3, 10, 117, 30, 3, 23, 45, 28, 4, 31, 24, 30, 11, 31, 15, 30,
        7, 7, 116, 30, 21, 7, 45, 28, 1, 37, 23, 30, 19, 26, 15, 30,
        5, 10, 115, 30, 19, 10, 47, 28, 15, 25, 24, 30, 23, 25, 15, 30,
        13, 3, 115, 30, 2, 29, 46, 28, 42, 1, 24, 30, 23, 28, 15, 30,
        17, 0, 115, 30, 10, 23, 46, 28, 10, 35, 24, 30, 19, 35, 15, 30,
        17, 1, 115, 30, 14, 21, 46, 28, 29, 19, 24, 30, 11, 46, 15, 30,
        13, 6, 115, 30, 14, 23, 46, 28, 44, 7, 24, 30, 59, 1, 16, 30,
        12, 7, 121, 30, 12, 26, 47, 28, 39, 14, 24, 30, 22, 41, 15, 30,
        6, 14, 121, 30, 6, 34, 47, 28, 46, 10, 24, 30, 2, 64, 15, 30,
        17, 4, 122, 30, 29, 14, 46, 28, 49, 10, 24, 30, 24, 46, 15, 30,
        4, 18, 122, 30, 13, 32, 46, 28, 48, 14, 24, 30, 42, 32, 15, 30,
        20, 4, 117, 30, 40, 7, 47, 28, 43, 22, 24, 30, 10, 67, 15, 30,
        19, 6, 118, 30, 18, 31, 47, 28, 34, 34, 24, 30, 20, 61, 15, 30
    }
    return tbl[i + 1]
end

-- alignment pattern
function Qr:adeltaLookup(i)
    local tbl = {
        0, 11, 15, 19, 23, 27, 31, --force 1 pat
        16, 18, 20, 22, 24, 26, 28, 20, 22, 24, 24, 26, 28, 28, 22, 24, 24,
        26, 26, 28, 28, 24, 24, 26, 26, 26, 28, 28, 24, 26, 26, 26, 28, 28
    }
    return tbl[i + 1]
end

-- version block
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
    self.framask[bt] = 1
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
    return self.framask[bt] > 0
end

-- Apply the selected mask out of the 8.
function Qr:applymask(m)
    if m == 0 then
        for y = 0, self.width - 1 do
            for x = 0, self.width - 1 do
                if bit32.band((x + y), 1) == 0 and not self:ismasked(x, y) then
                    self.qrframe[x + y * self.width] = bit32.bxor(self.qrframe[x + y * self.width], 1) --^
                end
            end
        end
    elseif m == 1 then
        for y = 0, self.width - 1 do
            for x = 0, self.width - 1 do
                if bit32.band(y, 1) == 0 and not self:ismasked(x, y) then
                    self.qrframe[x + y * self.width] = bit32.bxor(self.qrframe[x + y * self.width], 1) --^
                end
            end
        end
    elseif m == 2 then
        for y = 0, self.width - 1 do
            local rx = 0
            for x = 0, self.width - 1 do
                if rx == 3 then rx = 0 end
                if not rx and not self:ismasked(x, y) then
                    self.qrframe[x + y * self.width] = bit32.bxor(self.qrframe[x + y * self.width], 1) --^
                end
                rx = rx + 1
            end
        end
    end
end

local function printFrame(buffer, width, back, fill)
    back = back or "  "
    fill = fill or "##"
    for i = -3, width + 2 do
        local line = ""
        for j = 0, width - 1 do
            if i < 0 or i >= width then
                line = line .. back
            else
                line = line .. ((buffer[j * width + i] == 1) and fill or back)
            end
        end
        print(i, back .. back .. back .. line .. back .. back .. back)
    end
end

--Generate QR frame array
function Qr:genframe(instring)

    if self.progress == 0 then
        print("Qr: begin!")
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
            print("vsn", vsn)
            local k = (self.ecclevel - 1) * 4 + (vsn - 1) * 16
            self.neccblk1 = self:eccblocksLookup(k)
            k = k + 1
            self.neccblk2 = self:eccblocksLookup(k)
            k = k + 1
            self.datablkw = self:eccblocksLookup(k)
            k = k + 1
            self.eccblkwid = self:eccblocksLookup(k)
            k = self.datablkw * (self.neccblk1 + self.neccblk2) + self.neccblk2 - 3 + (self.version <= 9 and 1 or 0)
            if #instring <= k then
                self.version = vsn
                break
            end
        end
        self.resume = nil
        self.width = 17 + 4 * self.version;
        print("width version", self.width, self.version, getUsage())

        self.progress = self.progress + 1
        if (getUsage() > 50) then return end
    end

    if self.progress == 2 then
        -- allocate, clear and setup data structures
        local eccbufLen = self.datablkw + (self.datablkw + self.eccblkwid) * (self.neccblk1 + self.neccblk2) + self.neccblk2
        for t = 0, eccbufLen - 1 do
            self.eccbuf[t] = 0
        end

        for t = 0, self.width * self.width - 1 do
            self.qrframe[t] = 0
        end

        for t = 0, (self.width * (self.width + 1) + 1) / 2 - 1 do
            self.framask[t] = 0
        end
        print("QR: finished allocate", getUsage())

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
            self.qrframe[(y + 3) + self.width * (k + 3)] = 1
            for x = 0, 5 do
                self.qrframe[(y + x) + self.width * k] = 1
                self.qrframe[y + self.width * (k + x + 1)] = 1
                self.qrframe[(y + 6) + self.width * (k + x)] = 1
                self.qrframe[(y + x + 1) + self.width * (k + 6)] = 1
            end
            for x = 1, 4 do
                self:setmask(y + x, k + 1)
                self:setmask(y + 1, k + x + 1)
                self:setmask(y + 5, k + x)
                self:setmask(y + x + 1, k + 5)
            end
            for x = 2, 3 do
                self.qrframe[(y + x) + self.width * (k + 2)] = 1
                self.qrframe[(y + 2) + self.width * (k + x + 1)] = 1
                self.qrframe[(y + 4) + self.width * (k + x)] = 1
                self.qrframe[(y + x + 1) + self.width * (k + 4)] = 1
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

        print("QR: finished alignment", getUsage())
        self.progress = self.progress + 1
        if (getUsage() > 50) then return end
    end

    if self.progress == 4 then
        -- single black
        self.qrframe[8 + self.width * (self.width - 8)] = 1

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
                self.qrframe[(8 + x) + self.width * 6] = 1
                self.qrframe[6 + self.width * (8 + x)] = 1
            end
        end

        -- version block
        if self.version > 6 then
            local t = self:vpatLookup(self.version - 7 - 1)
            local k = 17
            for x = 0, 5 do
                for y = 0, 2 do -- and k--
                    if bit32.band(1, (k > 11 and bit32.rshift(self.version, (k - 12)) or bit32.rshift(t, k))) == 1 then
                        self.qrframe[(5 - x) + self.width * (2 - y + self.width - 11)] = 1
                        self.qrframe[(2 - y + self.width - 11) + self.width * (5 - x)] = 1
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
                if self.qrframe[x + self.width * y] == 1 then
                    self:setmask(x, y)
                end
            end
        end

        print("QR: finished basic fill", getUsage())
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
        print("QR: finished bitstream", getUsage())
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
        for i = self.resume.i, self.eccblkwid - 1 do
            self.resume.i = i
            if getUsage() > 40 then return end
            self.genpoly[i + 1] = 1;
            for j = i, 1, -1 do
                self.genpoly[j] = (self.genpoly[j] >= 1) and bit32.bxor(self.genpoly[j - 1], self:gexpLookup(self:modnn(self:glogLookup(self.genpoly[j]) + i))) or self.genpoly[j - 1] --^
            end
            self.genpoly[0] = self:gexpLookup(self:modnn(self:glogLookup(self.genpoly[0]) + i))
        end
        self.resume.i = self.resume.i + 1 --increment once more
        for j = self.resume.j, self.eccblkwid do --inclusive
            self.resume.j = j
            if getUsage() > 40 then return end
            self.genpoly[j] = self:glogLookup(self.genpoly[j]); -- use logs for genpoly[] to save calc step
        end
        self.resume = nil
        print("QR: genpoly", table ~= nil and table.unpack(self.genpoly) or "")
        print("QR: finished generator polynomial", getUsage())
        self.progress = self.progress + 1
        if (getUsage() > 50) then return end
    end

    if self.progress == 7 then
        -- append ecc to data buffer
        if self.resume == nil then
            self.resume = {blk=0, j=0, k=self.maxlength, y=0}
        end
        local ctx = self.resume
        print("neccblk 1 vs 2", self.neccblk1, self.neccblk2)
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
                    print("QR appendrs id", id, j)
                    local fb = self:glogLookup(bit32.bxor(self.strinbuf[ctx.y + id], self.strinbuf[ctx.k])) --^
                    if fb ~= 255 then     --fb term is non-zero
                        for jd = 1, self.eccblkwid - 1 do
                            self.strinbuf[ctx.k + jd - 1] = bit32.bxor(self.strinbuf[ctx.k + jd], self:gexpLookup(self:modnn(fb + self.genpoly[self.eccblkwid - jd]))) --^
                        end
                    else
                        for jd = ctx.k, ctx.k + self.eccblkwid - 1 do
                            self.strinbuf[jd] = self.strinbuf[jd + 1]
                        end
                    end
                    self.strinbuf[ctx.k + self.eccblkwid - 1] = fb == 255 and 0 or self:gexpLookup(self:modnn(fb + self.genpoly[0]))
                end
                ctx.id = nil
                ctx.y = ctx.y + self.datablkw + blk
                ctx.k = ctx.k + self.eccblkwid
                ctx.j = j
            end
            ctx.blk = blk
        end
        print("QR: finished appending ecc", getUsage())
        self.resume = nil
        self.progress = self.progress + 1
        if (getUsage() > 50) then return end
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
        print("QR: finished interleaving blocks", getUsage())
        self.progress = self.progress + 1
        if (getUsage() > 50) then return end
    end

    -- self:debugDump()
    -- quit()

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
                    self.qrframe[ctx.x + self.width * ctx.y] = 1
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
        print("QR: finished packing", getUsage())
        self.resume = nil
        self.progress = self.progress + 1
        if (getUsage() > 50) then return end
    end

    if self.progress == 10 then
        -- save pre-mask copy of frame
        self.strinbuf = {}

        -- self.strinbuf = shallowcopy(self.qrframe)
        local t = 0
        self:applymask(t);
        -- x = self.badcheck(); --TODO tim


        -- add in final mask/ecclevel bytes
        local y = self:fmtwordLookup(bit32.lshift(t + (self.ecclevel - 1), 3))
        -- low byte
        for bit = 0, 7 do
            if bit32.band(y, 1) == 1 then
                self.qrframe[(self.width - 1 - bit) + self.width * 8] = 1
                self.qrframe[8 + self.width * (bit + (bit < 6 and 0 or 1))] = 1
            end
            y = bit32.rshift(y, 1)
        end
        -- high byte
        for bit = 0, 6 do
            if bit32.band(y, 1) == 1 then
                self.qrframe[8 + self.width * (self.width - 7 + bit)] = 1
                self.qrframe[((bit >= 1) and (6 - bit) or 7) + self.width * 8] = 1
            end
            y = bit32.rshift(y, 1)
        end
        print("QR: finished appending ecc", getUsage())
        self.progress = 0
        --TODO self:reset
        return self.qrframe
    end
end

function Qr:debugDump()
    print("frame:")
    printFrame(self.qrframe, self.width)
    print("mask:")
    printFrame(self.framask, 16)
    print("eccbuf", table.unpack(self.eccbuf))
    print("strinbuf", table.unpack(self.strinbuf))
    print("genpoly", table.unpack(self.genpoly))
    print("eccblkwid", self.eccblkwid)
end

local loopc = 0
local str, qr, frame

local function run(event)
    loopc = loopc + 1
    print("OpenTX frame", loopc)
    if lcd ~= nil then
        lcd.drawFilledRectangle(0, 0, LCD_W, LCD_H, ERASE)
        local gpsfield = getFieldInfo("GPS")
        if gpsfield ~= nil then
            local gps = getValue(gpsfield.id)
            if type(gps) == "table" and gps.lat ~= nil and gps.lon ~= nil then
                lcd.drawText(0, 8, string.format("%.5f", gps.lat), SMLSIZE) --+ RIGHT)
                lcd.drawText(0, 16, string.format("%.5f", gps.lon), SMLSIZE)
            else
                lcd.drawText(0, 8, "no gps", SMLSIZE + RIGHT)
            end
        else
            lcd.drawText(0, 8, "no gps sensor", SMLSIZE)
        end
    end

    if loopc == 1 then
        str = "http://maps.google.com/?q=37.858784%2C-122.198935" --http://maps.google.com/?q=  GURU://
        qr = Qr:new(nil)
        print("new at ", getUsage())

    elseif loopc > 1 then
        frame = qr:genframe(str)
        print("Main loop exit at step:", qr.progress, "load:", getUsage(), "frame:", frame)
        if frame ~= nil then
            print("FINISHED")
            printFrame(frame, qr.width, "  ", "##")
            return 1
        end
    end
    return 0
end


if lcd == nil then
    local startTime
    function getUsage()
        return math.floor((os.clock() - startTime) * 100000)
    end
    print("defined getUsage")
    for i = 0, 50 do
        startTime = os.clock()
        if run() == 1 then return end
        repeat until (os.clock() - startTime) > 0.01
   end
    print("end running")
end

return { run = run }
