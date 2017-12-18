local fan = require "fan"
local http = require "http"

fan.loop(function()
    local ret = http.get{
        url = "https://www.baidu.com",
        headers = {
            ["test"] = "hahah"
        },
        onbodylength = function()
            return 100
        end,
        onbody = function(args, conn)
            conn:send(string.rep("A", 100))
        end
    }

    for k,v in pairs(ret) do
        print(k,v)
    end

    print(ret.body)
    os.exit()
end)
