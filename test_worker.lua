local fan = require "fan"
local worker = require "fan.worker"

local commander = worker.new({
    ["test"] = function(x, n, y, s)
        return n, math.random(x, y), nil, y, x, s
    end
}, 2)

fan.loop(function()
    fan.sleep(1)
    for k,v in pairs(commander.slaves) do
        print("commander.slaves",k,v)
    end
    while true do
        print(commander:test(1000, nil, 10000, "sss"))
        fan.sleep(1)
    end
end)

print("quit master")