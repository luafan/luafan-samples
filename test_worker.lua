local fan = require "fan"
local worker = require "fan.worker"
-- local md5 = require "md5"

local commander = worker.new({
    ["test"] = function(x, n, y, s)
        -- local d = md5.new()
        -- for i=1,1000 do
        --     d:update(s)
        -- end
        return n, math.random(x, y), nil, y, x, s--, d:digest()
    end
}, 4)

local function gettime()
  local sec,usec = fan.gettime()
  return sec + usec/1000000.0
end

fan.loop(function()
    local count = 0
    local last_count = 0
    local last_time = gettime()

    for i=1,100 do
        local co = coroutine.create(function()
            while true do
                commander:test(1000, nil, 10000, "sss")
                count = count + 1
                if count % 10000 == 0 then
                    print(string.format("count=%d speed=%1.03f", count, (count - last_count) / (gettime() - last_time)))

                    last_time = gettime()
                    last_count = count
                end
            end
        end)
        assert(coroutine.resume(co))
    end
end)

print("quit master")