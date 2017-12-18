package.cpath = "/usr/local/lib/?.so;" .. package.cpath

local config = require "config"
-- config.stream_ffi = true
config.stream_bit = true

local stream = require "fan.stream"

local s = stream.new()
s:AddS24(0xffffff)
s:AddS24(-8388608)
s:AddU16(0xffff)

s:AddU16(0xffff)
s:AddU16(0xffff)

s:AddU30(0x3FFFFFFF)
s:AddD64(12345.67891)
s:AddString("fan.stream")


local d = stream.new(s:package())
print(d:available())
assert(d:GetU24() == 0xffffff)
assert(d:GetS24() == -8388608)
assert(d:GetU16() == 0xffff)
assert(d:GetU32() == 0xffffffff)
assert(d:GetU30() == 0x3FFFFFFF)
assert(d:GetD64() == 12345.67891)

d:mark()
assert(d:GetString() == "fan.stream")
d:reset()
assert(d:GetString() == "fan.stream")

local buf,expect = d:GetString()
print(d:GetBytes() == nil)

print("test passed.")

local s = stream.new("aaaaa\nbbbbbb\r\ncccccccc\rddddddddd\n")
while true do
    local line = s:readline()
    if line then
        print(line)
    else
        break
    end
end
