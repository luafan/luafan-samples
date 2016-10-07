local fan = require "fan"
local connector = require "fan.connector"
local stream = require "fan.stream"

serv = connector.bind("fifo:test.fifo")

serv.onaccept = function(apt)
    print("onaccept", apt)
    apt.onread = function(input)
        print("onread", input:GetString())
    end

    while true do
        local output = stream.new()
        output:AddString(os.date())
        if not apt:send(output:package()) then
            print("break")
            break
        end
        fan.sleep(1)
    end
end

fan.loop()