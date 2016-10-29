local fan = require "fan"
local upnp = require "fan.upnp"
local cjson = require "cjson"

fan.loop(function()
    local obj = upnp.new(2)
    for i,v in ipairs(obj.devices) do
        print(cjson.encode(v))
    end

    print(obj:AddPortMapping("192.168.2.136", "10000", "10000", "udp"))

end)