require "compat53"
if jit then
  local v = require "jit.v"
  os.remove("objectbuf.log")
  v.on("objectbuf.log")
end
local config = require "config"
config.stream_ffi = false

local objectbuf = require "fan.objectbuf"
local fan = require "fan"
local utils = require "fan.utils"
local cjson = require "cjson"

ttt = "vvv"

local a = {
    -- foo = function(self, x, y)
    --     for i,v in ipairs(self.b) do
    --         print(i,v)
    --     end
    --     return math.random(x, y), ttt
    -- end,
    b = {
        1234556789,
        12345.6789,
        nil,
        -1234556789,
        -12345.6789,
        0,
        "asdfa",
        d = {
            e = f
        }
        -- function()end
    },
    averyvery = "long long textlong long textlong long textlong long textlong long textlong long textlong long textlong long textlong long textlong long textlong long textlong long text",
}

-- a.b.a = a

for i=1,10 do
    table.insert(a.b, "123456789012345678901234567890")
end

-- local cjson = require "cjson"
local sym = objectbuf.symbol({ b = {a = ""}, averyvery = ""})

local loopcount = 10000

local start = utils.gettime()
for i=1,loopcount do
    objectbuf.decode(objectbuf.encode(a))
end
print(utils.gettime() - start)

local start = utils.gettime()
for i=1,loopcount do
    objectbuf.decode(objectbuf.encode(a, sym), sym)
end
print(utils.gettime() - start)

local start = utils.gettime()
for i=1,loopcount do
    cjson.decode(cjson.encode(a))
end
print(utils.gettime() - start)


os.exit()
local buf = objectbuf.encode(a, sym)
print("#(buf)", #(buf)) -- , #(cjson.encode(a))

local f = io.open("buf.bin", "wb")
f:write(buf)
f:close()
-- os.exit()

local f = io.open("buf.bin", "rb")
local buf = f:read("*all")
f:close()

local obj = objectbuf.decode(buf, sym)

for i=1,10 do
    print(i, obj.b[i])
end

print(type(nil))

-- print(obj.b.a:foo(100, 200))
