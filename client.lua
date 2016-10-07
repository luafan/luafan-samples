local fan = require "fan"
local connector = require "fan.connector"

cli = assert(connector.connect("fifo:test.fifo"))

keepalive_co = coroutine.create(function()
    while true do
        local output = stream.new()
        output:AddString("keep alive")
        cli:send(output:package())
        print("keep aliving")
        fan.sleep(5)
    end
end)

print(coroutine.resume(keepalive_co))

fan.loop(function()
    while true do
        local input = cli:receive()
        if not input then
            print("break")
            break
        end

        print("onread", input:available(), input:GetString())

        local output = stream.new()
        output:AddString(os.time())
        cli:send(output:package())
    end
end)