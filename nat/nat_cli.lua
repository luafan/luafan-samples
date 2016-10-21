local fan = require "fan"
local config = require "config"
local connector = require "fan.connector"
local objectbuf = require "fan.objectbuf"
local utils = require "fan.utils"

local cjson = require "cjson"
require "compat53"

local sym = objectbuf.symbol(require "nat_dic")

local internal_host
local internal_port

for i,v in ipairs(fan.getinterfaces()) do
  if v.type == "inet" then
    print(cjson.encode(v))
    if v.name == "wlp3s0" or v.name == "en0" then
      internal_host = v.host
    end
  end
end

local cli = connector.connect("udp://120.27.39.178:10000")
local peer_map = {}
local bind_map = {}

local sync_port_running = nil

local index_conn_map = {}
local connkey_conn_map = {}

local command_map = {}

local ppkeepalive_map = {}
local allowed_map = {}

local clientkey = arg[1] and string.format("%s-%s", arg[1], utils.random_string(utils.LETTERS_W, 8)) or utils.random_string(utils.LETTERS_W, 16)

print("clientkey", clientkey)

local function sync_port()
  if sync_port_running then
    coroutine.resume(sync_port_running)
  end
end

local function send(msg, ...)
  msg.clientkey = clientkey
  -- print("send", cjson.encode(msg))
  return cli:send(objectbuf.encode(msg, sym), ...)
end

function command_map.list(host, port, msg)
  internal_port = cli.conn:getPort()
  print(cjson.encode(msg))

  allowed_map = {}
  for i,v in ipairs(msg.data) do
    local t = allowed_map[v.host]
    if not t then
      t = {}
      allowed_map[v.host] = t
    end
    t[v.port] = v

    if v.internal_host and v.internal_port then
      local t = allowed_map[v.internal_host]
      if not t then
        t = {}
        allowed_map[v.internal_host] = t
      end
      t[v.internal_port] = v
    end
  end

  for i,v in ipairs(msg.data) do
    print("list", i, cjson.encode(v))
    local peer = peer_map[v.clientkey]
    -- if not peer then
    -- print("send ppkeepalive", v.host, v.port)
    local output_index = send({type = "ppkeepalive"}, v.host, v.port)
    ppkeepalive_map[output_index] = true

    if v.internal_host and v.internal_port then
      local output_index = send({type = "ppkeepalive"}, v.internal_host, v.internal_port)
      ppkeepalive_map[output_index] = true
    end
    -- else
    -- print("ignore nat", v.clientkey, peer)
    -- end
  end
end

function command_map.ppconnect(host, port, msg)
  local peer = peer_map[msg.clientkey]
  local obj

  print(host, port, cjson.encode(msg))

  obj = {
    connkey = msg.connkey,
    peer = peer,
    host = host,
    port = port,
    forward_index = nil,
    auto_index = 0,
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
      ondisconnected = function(msgstr)
        print("remote disconnected", msgstr)
        send({type = "ppdisconnectedmaster", connkey = msg.connkey}, obj.host, obj.port)
      end
    }
  }

  connkey_conn_map[msg.connkey] = obj
  peer.conn_map[msg.connkey] = obj
end

function command_map.ppconnected(host, port, msg)
  print(host, port, cjson.encode(msg))

  local obj = connkey_conn_map[msg.connkey]
  obj.connected = true

  sync_port()
end

function command_map.ppdisconnectedmaster(host, port, msg)
  print(host, port, cjson.encode(msg))
  local obj = connkey_conn_map[msg.connkey]
  connkey_conn_map[msg.connkey] = nil
  -- clean up client apt.
  if obj then
    obj.t.conn_map[obj.apt] = nil
    obj.apt:close()
    obj.apt = nil
  end
end

function command_map.ppdisconnectedclient(host, port, msg)
  print(host, port, cjson.encode(msg))
  local obj = connkey_conn_map[msg.connkey]
  -- clean up server conn.
  if obj then
    obj.peer.conn_map[msg.connkey] = nil
    connkey_conn_map[msg.connkey] = nil
    obj.conn:close()
    obj.conn = nil
  end
end

function command_map.ppdata_req(host, port, msg)
  local obj = connkey_conn_map[msg.connkey]
  obj.conn:send(msg.data)

  msg.data = nil
  print(os.date("%X"), host, port, cjson.encode(msg))
end

function command_map.ppdata_resp(host, port, msg)
  local obj = connkey_conn_map[msg.connkey]
  obj.apt:send(msg.data)

  local len = #(msg.data)
  msg.data = nil
  print(os.date("%X"), host, port, cjson.encode(msg), len)
end

function command_map.ppkeepalive(host, port, msg)
  print(os.date("%X"), host, port, cjson.encode(msg))

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
    send{type = "list", internal_host = internal_host, internal_port = internal_port}
    -- send{type = "keepalive"}
    fan.sleep(3)
    print(string.format("udp send: %d, receive: %d", config.udp_send_total, config.udp_receive_total))
  end
end

local function keepalive_peers()
  while true do
    sync_port()
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
          obj.auto_index = obj.auto_index + 1
          obj.forward_index = send({type = "ppdata_resp", connkey = connkey, data = data, index = obj.auto_index}, obj.host, obj.port)
          print("forwarding to client", obj.forward_index)
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
        obj.auto_index = obj.auto_index + 1
        obj.forward_index = send({type = "ppdata_req", connkey = connkey, data = data, index = obj.auto_index}, obj.host, obj.port)
        print("forwarding to server", obj.forward_index)
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
      local msg = objectbuf.decode(body, sym)
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
      elseif ppkeepalive_map[index] then
        ppkeepalive_map[index] = nil
      end
    end

    cli.ontimeout = function(package, host, port)
      if host and port then
        local alive = allowed_map[host] and allowed_map[host][port]
        if not alive then
          print("drop", #(package), host, port)
          return false
        else
          local output_index = string.unpack("<I2", package)
          if ppkeepalive_map[output_index] then
            ppkeepalive_map[output_index] = nil
            print("drop ppkeepalive")
            return false
          end
        end
      else
        return true
      end

      return true
    end

    coroutine.wrap(list_peers)()
    coroutine.wrap(keepalive_peers)()
    coroutine.wrap(sync_port_buffers)()

    local connkey_index = 0

    local httpd = require "fan.httpd"
    debug_console_serv = httpd.bind{
      port = tonumber(arg[2]),
      onService = function(req, resp)
        local params = req.params
        if params.action == "incoming" then
          resp:addheader("Content-Type", "text/plain; charset=UTF-8")
          resp:reply_start(200, "OK")
          for key,incoming in pairs(cli._incoming_map) do
            resp:reply_chunk(string.format("%s\n", key))
            for output_index,incoming_object in pairs(incoming) do
              if incoming_object.done then
                resp:reply_chunk(string.format("%06d\treceived %d\n", output_index, incoming_object.count))
              else
                local count = 0
                for idx,body in pairs(incoming_object.items) do
                  count = count + 1
                end

                resp:reply_chunk(string.format("%06d\treceiving %d/%d\n", output_index, count, incoming_object.count))
              end
            end
          end
          return resp:reply_end()
        elseif params.action == "bind" then
          local port = tonumber(params.port)
          if bind_map[port] then
            return resp:reply(200, "OK", "bind already.")
          end

          local peer = nil
          for k,v in pairs(peer_map) do
            if k:find(params.clientkey) == 1 then
              peer = v
              break
            end
          end
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
                  auto_index = 0,
                }

                connkey_index = connkey_index + 1
                d.connkey = connkey_index

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
