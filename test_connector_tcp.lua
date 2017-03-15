local fan = require "fan"
local connector = require "fan.connector"

local co = coroutine.create(function()
    serv = connector.bind("tcp://127.0.0.1:10000")
    serv.onaccept = function(apt)
        print("onaccept")
        while true do
            local input = apt:receive()
            if not input then
                break
            end

            local buf = input:GetBytes()
            apt:send(buf)
        end
    end
end)
coroutine.resume(co)

local data = string.rep("a", 1492)

fan.loop(function()
    cli = connector.connect("tcp://127.0.0.1:10000")
    cli:send("hi")

    coroutine.wrap(function()
        while true do
            fan.sleep(1)
            cli:send("hi")
            print("sent")
        end
        end)()

    while true do
        local input = cli:receive()
        if not input then
            break
        end

        -- print("client read", input)
        input:GetBytes()

        cli:send(data)
     end
end)
