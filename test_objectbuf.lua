require "compat53"

local objectbuf = require "fan.objectbuf"
local fan = require "fan"
local utils = require "fan.utils"
local cjson = require "cjson"

local a = {
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
    },
    averyvery = "long long textlong long textlong long textlong long textlong long textlong long textlong long textlong long textlong long textlong long textlong long textlong long text",
}

-- a.b.a = a
-- set same random seed for benchmark.
math.randomseed(0)

for i=1,100 do
    table.insert(a.b, string.rep("abc", math.random(1000)))
end

local sym = objectbuf.symbol(a)

local loopcount = 10000

local data = objectbuf.encode(a)
local data_sym = objectbuf.encode(a, sym)
local data_json = cjson.encode(a)

local start = utils.gettime()
for i=1,loopcount do
    objectbuf.encode(a)
end
print("objectbuf.encode", utils.gettime() - start)

local start2 = utils.gettime()
for i=1,loopcount do
    objectbuf.decode(data)
end
print("objectbuf.decode", utils.gettime() - start2)
print("objectbuf\n", utils.gettime() - start)

local start = utils.gettime()
for i=1,loopcount do
    objectbuf.encode(a, sym)
end
print("objectbuf.encode_sym", utils.gettime() - start)

local start2 = utils.gettime()
for i=1,loopcount do
    objectbuf.decode(data_sym, sym)
end
print("objectbuf.decode_sym", utils.gettime() - start2)
print("objectbuf.sym\n", utils.gettime() - start)

local start = utils.gettime()
for i=1,loopcount do
    cjson.encode(a)
end
print("cjson.encode", utils.gettime() - start)

local start2 = utils.gettime()
for i=1,loopcount do
    cjson.decode(data_json)
end
print("cjson.decode", utils.gettime() - start2)
print("cjson\n", utils.gettime() - start)

-- os.exit()
