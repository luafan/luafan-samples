local fan = require "fan"
local connector = require "fan.connector"
local objectbuf = require "fan.objectbuf"
local utils = require "fan.utils"

local cjson = require "cjson"
require "compat53"

local cli = connector.connect("udp://127.0.0.1:10000")
local peer_map = {}
local bind_map = {}

local sync_port_running = nil

local index_conn_map = {}
local connkey_conn_map = {}

local command_map = {}

local clientkey = arg[1] or utils.random_string(utils.LETTERS_W, 8)

print("clientkey", clientkey)

local function sync_port()
  if sync_port_running then
    coroutine.resume(sync_port_running)
  end
end

local function send(msg, ...)
  msg.clientkey = clientkey
  return cli:send(objectbuf.encode(msg), ...)
end

function command_map.list(host, port, msg)
  for i,v in ipairs(msg.data) do
    local peer = peer_map[v.clientkey]
    -- if not peer then
    send({type = "ppkeepalive"}, v.host, v.port)
    -- else
    -- print("ignore nat", v.clientkey, peer)
    -- end
  end
end

function command_map.ppconnect(host, port, msg)
  local peer = peer_map[msg.clientkey]
  local obj

  obj = {
    connkey = connkey,
    peer = peer,
    host = host,
    port = port,
    forward_index = nil,
    input_queue = {},
    conn = tcpd.connect{
      host = msg.host,
      port = msg.port,
      onconnected = function()
        print("onconnected")
        send({type = "ppconnected", connkey = msg.connkey}, host, port)
      end,
      onread = function(buf)
        table.insert(obj.input_queue, buf)
        sync_port()
      end,
      ondisconnected = function(msg)
        print("remote disconnected", msg)
        send({type = "ppdisconnectedmaster", connkey = msg.connkey}, obj.host, obj.port)
      end
    }
  }

  connkey_conn_map[msg.connkey] = obj
  peer.conn_map[msg.connkey] = obj
end

function command_map.ppconnected(host, port, msg)
  local obj = connkey_conn_map[msg.connkey]
  obj.connected = true

  sync_port()
end

function command_map.ppdisconnectedmaster(host, port, msg)
  local obj = connkey_conn_map[msg.connkey]
  connkey_conn_map[msg.connkey] = nil
  -- clean up client apt.

  obj.t.conn_map[obj.apt] = nil
  obj.apt:close()
  obj.apt = nil
end

function command_map.ppdisconnectedclient(host, port, msg)
  local obj = connkey_conn_map[msg.connkey]
  -- clean up server conn.
  obj.peer.conn_map[msg.connkey] = nil
  connkey_conn_map[msg.connkey] = nil
  obj.conn:close()
  obj.conn = nil
end

function command_map.ppdata_req(host, port, msg)
  local obj = connkey_conn_map[msg.connkey]
  obj.conn:send(msg.data)
end

function command_map.ppdata_resp(host, port, msg)
  local obj = connkey_conn_map[msg.connkey]
  obj.apt:send(msg.data)
end

function command_map.ppkeepalive(host, port, msg)
  -- print(host, port, cjson.encode(msg))

  local peer = peer_map[msg.clientkey]
  if not peer then
    peer = {host = host, port = port, last_keepalive = utils.gettime(), conn_map = {}}
    peer_map[msg.clientkey] = peer
  else
    peer.last_keepalive = utils.gettime()
  end
end

local function list_peers()
  while true do
    send{type = "list"}
    -- send{type = "keepalive"}
    fan.sleep(1)
  end
end

local function keepalive_peers()
  while true do
    for k,v in pairs(peer_map) do
      send({type = "ppkeepalive"}, v.host, v.port)
    end

    for k,v in pairs(peer_map) do
      if utils.gettime() - v.last_keepalive > 30 then
        cli:cleanup(v.host, v.port)
        print(k, "keepalive timeout.")
        for port,t in pairs(bind_map) do
          if t.peer == v then
            print("cleanup port", port)
            for apt,d in pairs(t.conn_map) do
              apt:close()
              t.conn_map[apt] = nil
            end
            t.serv:close()
            t.serv = nil
            bind_map[port] = nil
          end
        end
        peer_map[k] = nil
      end
    end

    fan.sleep(10)
  end
end

local function sync_port_buffers()
  while true do
    local count = 0
    for ckey,peer in pairs(peer_map) do
      for connkey,obj in pairs(peer.conn_map) do
        if not obj.forward_index and #(obj.input_queue) > 0 then
          local data = table.concat(obj.input_queue)
          obj.input_queue = {}
          obj.forward_index = send({type = "ppdata_resp", connkey = connkey, data = data}, obj.host, obj.port)
          -- print("forward to client", obj.forward_index)
          index_conn_map[obj.forward_index] = obj
          count = count + 1
        end
      end
    end

    for connkey,obj in pairs(connkey_conn_map) do
      -- print(obj, obj.connected, obj.forward_index, #(obj.input_queue))
      if obj.connected and not obj.forward_index and #(obj.input_queue) > 0 then
        local data = table.concat(obj.input_queue)
        obj.input_queue = {}
        obj.forward_index = send({type = "ppdata_req", connkey = connkey, data = data}, obj.host, obj.port)
        -- print("forward to server", obj.forward_index)
        index_conn_map[obj.forward_index] = obj
        count = count + 1
      end
    end

    sync_port_running = coroutine.running()
    coroutine.yield()
    sync_port_running = nil
  end
end

fan.loop(function()
    -- cli = connector.connect("udp://mkgitserver.successinfo.com.cn:8802")
    cli.onread = function(body, host, port)
      local msg = objectbuf.decode(body)
      -- print(host, port, cjson.encode(msg))

      local command = command_map[msg.type]
      if command then
        command(host, port, msg)
      end
    end

    cli.onsent = function(index)
      local obj = index_conn_map[index]

      if obj then
        obj.forward_index = nil
        sync_port()
      end
    end

    coroutine.wrap(list_peers)()
    coroutine.wrap(keepalive_peers)()
    coroutine.wrap(sync_port_buffers)()

    local httpd = require "fan.httpd"
    serv = httpd.bind{
      port = tonumber(arg[2]),
      onService = function(req, resp)
        local params = req.params
        if params.action == "bind" then
          local port = tonumber(params.port)
          if bind_map[port] then
            return resp:reply(200, "OK", "bind already.")
          end

          local peer = peer_map[params.clientkey]
          if not peer then
            return resp:reply(200, "OK", "NAT not completed.")
          end

          local t
          t = {
            port = port,
            peer = peer,
            remote_host = params.remote_host,
            remote_port = params.remote_port,
            clientkey = params.clientkey,
            conn_map = {},

            serv = tcpd.bind{
              port = port,
              onaccept = function(apt)
                local d = {
                  input_queue = {},
                  apt = apt,
                  t = t,
                  host = peer.host,
                  port = peer.port,
                  forward_index = nil,
                  connkey = utils.random_string(utils.LETTERS_W, 16)
                }

                t.conn_map[apt] = d
                connkey_conn_map[d.connkey] = d

                send({
                    type = "ppconnect",
                    connkey = d.connkey,
                    host = params.remote_host,
                    port = params.remote_port
                  }, peer.host, peer.port)

                apt:bind{
                  onread = function(buf)
                    table.insert(d.input_queue, buf)

                    sync_port()
                  end,
                  ondisconnected = function(msg)
                    print("client disconnected", msg)
                    t.conn_map[apt] = nil
                    d.connected = nil
                    send({type = "ppdisconnectedclient", connkey = d.connkey}, peer.host, peer.port)
                  end
                }
              end
            }
          }

          bind_map[port] = t
          return resp:reply(200, "OK", "submitted.")
        end
      end
    }
  end)
