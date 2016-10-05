local fan = require "fan"
local connector = require "fan.connector"
local stream = require "fan.stream"

serv = connector.bind("fifo:test.fifo")

serv.onaccept = function(apt)
    print("onaccept", apt)
    apt.onread = function(input)
        print("onread", input:GetString())
    end

    for i=1,10 do
        if apt.disconnected then
            break
        end
        local output = stream.new()
        output:AddString(os.date())
        apt.fifo_write:send(output:package())
        fan.sleep(1)
        print("wake")
    end
end

fan.loop()