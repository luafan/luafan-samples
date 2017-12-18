local fan = require "fan"
local http = require "fan.http"

local c = tonumber(arg[1])
local n = tonumber(arg[2])
local url = arg[3]

fan.loop(function()
    http.cookiejar("/dev/null")
    local reqcount = 0
    for i=1,c do
        local co = coroutine.wrap(function()
            local running = coroutine.running()
            while true do
                local ret = http.get(url)
                -- print(ret.responseCode, ret.body)
                reqcount = reqcount + 1
            end
        end)()
    end

    local utils = require "fan.utils"
    local lasttime = utils.gettime()
    local lastcount = 0

    while true do
        fan.sleep(2)

        print("speed", (reqcount - lastcount) / (utils.gettime() - lasttime))

        if reqcount > n then
          os.exit()
        end
        lastcount = reqcount
        lasttime = utils.gettime()
    end
end)
