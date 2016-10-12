local fan = require "fan"
local worker = require "fan.worker"
local md5 = require "md5"

local slave_task_level = tonumber(arg[3] or 0)

local commander = worker.new({
    ["test"] = function(x, n, y, s)
      if slave_task_level > 0 then
        local d = md5.new()
        for i=1,slave_task_level do
          d:update("tt")
        end
        return d:digest()
      end
    end
  }, tonumber(arg[1] or 3), tonumber(arg[2] or 1))

local function gettime()
  local sec,usec = fan.gettime()
  return sec + usec/1000000.0
end

fan.loop(function()
    local count = 0
    local last_count = 0
    local last_time = gettime()

    fan.sleep(1)

    for i=1,20 do
      local co = coroutine.create(function()
          while true do
            commander:test(1000)
            count = count + 1
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
      print(string.format("count=%d speed=%1.03f", count, (count - last_count) / (gettime() - last_time)))
      last_time = gettime()
      last_count = count
      for i,v in ipairs(commander.slaves) do
        print(i, v.task_index, v.status, v.jobcount)
      end
    end
  end)

print("quit master")
