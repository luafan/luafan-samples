local fan = require "fan"
local connector = require "fan.connector"

cli = assert(connector.connect("fifo:test.fifo"))

cli.onread = function(input)
    print("onread", input:available(), input:GetString())
    local output = stream.new()
    output:AddString(os.time())
    cli.fifo_write:send(output:package())
end

fan.loop()