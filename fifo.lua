--[[

luajit fifo.lua

-- another shell
echo test > fan.fifo
-- or
cat fan2.fifo

]]

local fan = require "fan"
local fifo = require "fan.fifo"

p1 = fifo.connect{
    name = "fan.fifo",
    rwmode = "r",
    onread = function(buf)
        print("onread", #(buf), buf)
    end
}

fan.loop(function()
    local count = 1
    local loop = true

    while loop do
        fan.sleep(1)

        if not p2 then
            p2 = fifo.connect{
                name = "fan2.fifo",
                rwmode = "w",

                onsendready = function()
                    count = count + 1
                    if count > 5 then
                        p2 = nil
                        loop = false
                        collectgarbage()
                    else
                        p2:send(string.format("new send %d\n", count))
                    end
                end,
                ondisconnected = function(msg)
                    print("ondisconnected", msg)
                    p2 = nil
                end
            }
        end

        if p2 then
           p2:send_req()
        end
     end

end)
