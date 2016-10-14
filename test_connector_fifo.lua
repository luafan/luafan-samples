local fan = require "fan"
local connector = require "fan.connector"

local fifoname = connector.tmpfifoname()
local url = "fifo:" .. fifoname

local co = coroutine.create(function()
    serv = connector.bind(url)
    serv.onaccept = function(apt)
        print("onaccept")
        while true do
            local input = apt:receive()
            if not input then
                break
            end
            print("serv read", input)

            apt:send(input:GetBytes())
        end
    end
end)
print(coroutine.resume(co))

fan.loop(function()
    cli = connector.connect(url)
    print(cli:send("hi"))

    while true do
        local input = cli:receive()
        if not input then
            break
        end

        print("client read", input)
        print(input:GetBytes())

        cli:send(os.date())
     end
end)
