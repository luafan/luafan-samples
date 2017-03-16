local fan = require "fan"
local utils = require "fan.utils"
local worker = require "fan.worker"

local commander = worker.new({
    ["test"] = function(x, y)
      error("you should not see this as slave count is 0")
    end
  }, 0, tonumber(arg[1] or 10), "tcp://127.0.0.1:10000")

fan.loop(function()
    local count = 0
    local last_count = 0
    local last_time = utils.gettime()

    for i=1,20 do
      local co = coroutine.create(function()
          local data = string.rep("abc", 1024)
          while true do
            local status, x, y = commander:test(1000, data)
            if status then
              assert(x == data)
              assert(y == "3437d873715e86d96e373929b63a3b28")
              count = count + 1
            else
              print(x)
            end
          end
        end)
      local st,msg = coroutine.resume(co)
      if not st then
        print(msg)
      else
        print("started")
      end
    end

    while true do
      fan.sleep(2)
      print(string.format("count=%d speed=%1.03f", count, (count - last_count) / (utils.gettime() - last_time)))
      last_time = utils.gettime()
      last_count = count
      for i,v in ipairs(commander.slaves) do
        print(i, v.task_index, v.status, v.jobcount)
      end
    end
  end)

print("quit master")
