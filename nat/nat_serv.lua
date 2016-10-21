local fan = require "fan"
local connector = require "fan.connector"
local objectbuf = require "fan.objectbuf"
local utils = require "fan.utils"

local cjson = require "cjson"
require "compat53"

local sym = objectbuf.symbol(require "nat_dic")

local conn_map = {}
local command_map = {}

function command_map.list(apt, msg)
  local conn = conn_map[apt]
  if msg.clientkey then
    conn.clientkey = msg.clientkey
  end
  if msg.internal_host and msg.internal_port then
    conn.internal_host = msg.internal_host
    conn.internal_port = msg.internal_port
  end

  local t = {}
  local current_time = utils.gettime()

  for k,v in pairs(conn_map) do
    if k ~= apt then
      if apt.host == k.host then
        if v.internal_host and v.internal_port then
          table.insert(t, {
              host = v.internal_host,
              port = v.internal_port,
              clientkey = v.clientkey,
            })
        end
      else
        table.insert(t, {
            host = k.host,
            port = k.port,
            internal_host = v.internal_host,
            internal_port = v.internal_port,            
            clientkey = v.clientkey,
          })
      end
    end
  end

  apt:send(objectbuf.encode({type = msg.type, data = t}, sym))
end

fan.loop(function()
    serv = connector.bind("udp://0.0.0.0:10000")
    serv.onaccept = function(apt)
      print("onaccept")
      conn_map[apt] = {last_keepalive = utils.gettime()}

      apt.onread = function(body)
        conn_map[apt].last_keepalive = utils.gettime()

        local msg = objectbuf.decode(body, sym)
        print(apt.host, apt.port, cjson.encode(msg))

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
