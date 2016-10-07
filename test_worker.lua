local fan = require "fan"
local worker = require "fan.worker"

local commander = worker.new({
    ["test"] = function(x, y)
        return math.random(x, y), nil, y, x
    end
}, 2)

fan.loop(function()
    fan.sleep(2)
    for k,v in pairs(commander.slaves) do
        print("commander.slaves",k,v)
    end
    while true do
        print(commander:test(1000, 10000))
        fan.sleep(1)
    end
end)

print("quit master")