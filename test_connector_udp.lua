if jit then
  local v = require "jit.v"
  os.remove("connector_udp.log")
  v.on("connector_udp.log")
end

local fan = require "fan"
local config = require "config"

local utils = require "fan.utils"
local connector = require "fan.connector"

config.udp_check_timeout_duration = 10

if fan.fork() > 0 then
  local longstr = string.rep("abc", 333333)
  print(#(longstr))

  fan.loop(function()
      fan.sleep(1)
      cli = connector.connect("udp://127.0.0.1:10000")
      cli.onread = function(body)
        -- print("cli onread", #(body))
        assert(body == longstr)
        -- local start = utils.gettime()
        cli:send(longstr)
        -- print(utils.gettime() - start)
      end
      -- local start = utils.gettime()
      cli:send(longstr)
      -- print(utils.gettime() - start)

      -- while true do
      --   collectgarbage()
      --   print(collectgarbage("count"))

      --   fan.sleep(2)
      -- end
    end)
else
  local co = coroutine.create(function()
      serv = connector.bind("udp://127.0.0.1:10000")
      serv.onaccept = function(apt)
        print("onaccept")
        apt.onread = function(body)
          -- print("apt onread", #(body))
          -- print(apt.host, apt.port, apt.dest)
          apt:send(body)
        end
      end
    end)
  assert(coroutine.resume(co))

  fan.loop(function()
      -- while true do
      --   collectgarbage()
      --   print(collectgarbage("count"))

      --   fan.sleep(2)
      -- end
    end)

end
