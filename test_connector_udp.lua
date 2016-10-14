local fan = require "fan"
local connector = require "fan.connector"
require "compat53"

local co = coroutine.create(function()
    serv = connector.bind("udp://127.0.0.1:10000")
    serv.onaccept = function(apt)
        print("onaccept")
        apt.onread = function(body)
            print("apt onread", #(body))
            apt:send(body)
        end
    end
end)
assert(coroutine.resume(co))

local longstr = string.rep("a", 1024*1024)

fan.loop(function()
    cli = connector.connect("udp://127.0.0.1:10000")
    cli.onread = function(body)
        print("cli onread", #(body))
        assert(body == longstr)
        cli:send(longstr)
    end
    cli:send(longstr)
end)