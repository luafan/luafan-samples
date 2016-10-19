local fan = require "fan"
local connector = require "fan.connector"
local objectbuf = require "fan.objectbuf"
local utils = require "fan.utils"

local cjson = require "cjson"
require "compat53"

local conn_map = {}
local command_map = {}

function command_map.list(apt, msg)
  local conn = conn_map[apt]
  if not conn.clientkey then
    conn.clientkey = msg.clientkey
  end

  local t = {}
  local current_time = utils.gettime()

  for k,v in pairs(conn_map) do
    if k ~= apt then
      local dest = k.dest
      table.insert(t, {
          host = dest:getHost(),
          port = dest:getPort(),
          clientkey = v.clientkey,
        })
    end
  end

  apt:send(objectbuf.encode{type = msg.type, data = t})
end

fan.loop(function()
    serv = connector.bind("udp://127.0.0.1:10000")
    serv.onaccept = function(apt)
      print("onaccept")
      conn_map[apt] = {last_keepalive = utils.gettime()}

      apt.onread = function(body)
        conn_map[apt].last_keepalive = utils.gettime()

        local msg = objectbuf.decode(body)
        print(cjson.encode(msg))

        local command = command_map[msg.type]
        if command then
          command(apt, msg)
        end
      end
    end

    while true do
      for k,v in pairs(conn_map) do
        if utils.gettime() - v.last_keepalive > 30 then
          print(k.dest, "keepalive timeout.")
          k:cleanup()
          conn_map[k] = nil
        end
      end

      fan.sleep(1)
    end
  end)
