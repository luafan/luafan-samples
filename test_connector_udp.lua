local fan = require "fan"
local config = require "config"

-- override config settings.
-- config.debug = true
config.udp_mtu = 8192
config.udp_waiting_count = 10000
config.udp_package_timeout = 3

local utils = require "fan.utils"
local connector = require "fan.connector"

local function count_table_size(t, n, level)
    if not n then
        n = 1
    end
    if not level then
        level = 1
    end

    local count = 0
    for k, v in pairs(t) do
        if n > level then
            count = count + count_table_size(v, n, level + 1)
        else
            count = count + 1
        end
    end

    return count
end

local function count_chain_size(t)
    local count = 0
    local cursor = t._head
    while cursor do
        count = count + 1
        cursor = cursor._next
    end

    return count
end

if fan.fork() > 0 then
  math.randomseed(utils.gettime())

  local longstr = string.rep("abc", 10240)
  print(#(longstr))

  fan.loop(function()
      fan.sleep(1)
      cli = connector.connect("udp://localhost:10000")

      local count = 0
      local last_count = 0
      local last_time = utils.gettime()

      coroutine.wrap(function()
          while true do
            fan.sleep(2)
            print(string.format("count=%d speed=%1.03f",
              count, (count - last_count) / (utils.gettime() - last_time)),
              config.udp_send_total, config.udp_receive_total, config.udp_resend_total,
              count_table_size(cli._output_wait_package_parts_map),
              count_table_size(cli._output_wait_ack),
              count_chain_size(cli._output_chain),
              cli._send_window, cli._recv_window,
              count_table_size(cli._send_window_holes), count_table_size(cli._recv_window_holes)
            )
            last_time = utils.gettime()
            last_count = count
          end
      end)()

      cli.onread = function(body)
        -- print("cli.onread", #body)
        count = count + 1
        -- print("cli onread", #(body))
        -- assert(body == longstr)
        -- local start = utils.gettime()
        cli:send(longstr)
        -- print(utils.gettime() - start)
      end

      cli:send(longstr)
    end)
else
  math.randomseed(utils.gettime())

  local co = coroutine.create(function()
      serv = connector.bind("udp://localhost:10000")
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
