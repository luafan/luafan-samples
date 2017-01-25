local fan = require "fan"
local utils = require "fan.utils"

local function gettime()
    local sec,usec = fan.gettime()
    return sec + usec/1000000.0
end

local utils_gettime = utils.gettime

local start = utils.gettime()

for i=1,10000000 do
    gettime()
end

print("gettime", utils.gettime() - start)

local start = utils.gettime()

for i=1,10000000 do
    utils_gettime()
end

print("utils.gettime", utils.gettime() - start)