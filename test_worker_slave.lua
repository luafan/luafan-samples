local fan = require "fan"
local utils = require "fan.utils"
local worker = require "fan.worker"
local md5 = require "md5"

local slave_task_level = tonumber(arg[3] or 0)

local commander = worker.new({
    ["test"] = function(x, y)
      -- local d = md5.new()
      -- d:update(y)
      -- return y, d:digest()
      return y, x
    end
  }, 1, tonumber(arg[2] or 10), "tcp://127.0.0.1:10000") --  "tcp://127.0.0.1:10000"

fan.loop(function()
  while true do
    fan.sleep(60)
  end
end)
print("quit")
