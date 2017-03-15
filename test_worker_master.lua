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
  }, 0, tonumber(arg[2] or 10), "tcp://127.0.0.1:10000")

fan.loop(function()
    local count = 0
    local last_count = 0
    local last_time = utils.gettime()


    for i=1,20 do
      local co = coroutine.create(function()
          local data = string.rep("a", 102400)
          while true do
            local st,msg = pcall(function()
              local status, x, y = commander:test(1000, data)
              if status then
                assert(x == data)
                -- assert(y == "7202826a7791073fe2787f0c94603278")
                count = count + 1
              else
                print(x)
              end
            end)
            if not st then
              print(msg)
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
