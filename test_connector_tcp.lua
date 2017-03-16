local fan = require "fan"
local connector = require "fan.connector"
local utils = require "fan.utils"

local co = coroutine.create(function()
    serv = connector.bind("tcp://127.0.0.1:10000")
    serv.onaccept = function(apt)
        -- apt.simulate_send_block = false
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

fan.loop(function()
    cli = connector.connect("tcp://127.0.0.1:10000")
    -- cli.simulate_send_block = false
    cli:send("hi")

    coroutine.wrap(function()
        while true do
            fan.sleep(1)
            cli:send("noise")
        end
        end)()

    local count = 0
    local last_count = 0
    local last_time = utils.gettime()

    coroutine.wrap(function()
        while true do
          fan.sleep(2)
          print(string.format("count=%d speed=%1.03f", count, (count - last_count) / (utils.gettime() - last_time)))
          last_time = utils.gettime()
          last_count = count
        end
    end)()

    while true do
        local input = cli:receive()
        if not input then
            break
        end

        -- print("client read", input)
        input:GetBytes()
        count = count + 1

        cli:send(os.date())
     end
end)
