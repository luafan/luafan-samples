local fan = require "fan"
local config = require "config"

local utils = require "fan.utils"
local connector = require "fan.connector"

config.udp_check_timeout_duration = 10

if fan.fork() > 0 then
  local longstr = string.rep("abc", 3)
  print(#(longstr))

  fan.loop(function()
      fan.sleep(1)
      cli = connector.connect("udp://127.0.0.1:10000")

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

      cli.onread = function(body)
        count = count + 1
        -- print("cli onread", #(body))
        assert(body == longstr)
        -- local start = utils.gettime()
        cli:send(longstr)
        -- print(utils.gettime() - start)
      end

      cli:send(longstr)
    end)
else
  local co = coroutine.create(function()
      serv = connector.bind("udp://127.0.0.1:10000")
      serv.onaccept = function(apt)
        print("onaccept")
        apt.onread = function(body)
          -- print("apt onread", #(body))
          apt:send(body)
        end
      end
    end)
  assert(coroutine.resume(co))

  fan.loop()

end
