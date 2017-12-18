local fan = require "fan"
local tcpd = require "fan.tcpd"

fan.loop(function()
    local conn = tcpd.connect{
        host = "www.baidu.com",
        port = 443,
        ssl = true,
        cainfo = "cert.pem",
        onread = function (buf)
            print(buf)
        end
    }

    conn:send("GET / HTTP/1.0\r\nHost: www.baidu.com\r\n\r\n")

    -- os.exit()
end)
