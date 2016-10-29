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
local internal_netmask

for i,v in ipairs(fan.getinterfaces()) do
  if v.type == "inet" then
    print(cjson.encode(v))
    if v.name == "wlp3s0" or v.name == "en0" or v.name == "eth0" then
      internal_host = v.host
      internal_netmask = v.netmask
    end
  end
end

local REMOTE_HOST = "120.27.39.178"
local REMOTE_PORT = 10000

remote_serv = nil

local peer_map = {}
local bind_map = {}

local sync_port_running = nil

local command_map = {}

local allowed_map = {}

local clientkey = arg[1] and string.format("%s-%s", arg[1], utils.random_string(utils.LETTERS_W, 8)) or utils.random_string(utils.LETTERS_W, 16)

print("clientkey", clientkey)

local function sync_port()
  if sync_port_running then
    coroutine.resume(sync_port_running)
  end
end

local function get_peer(apt)
  for k,v in pairs(peer_map) do
    if v.apt == apt then
      return v
    end
  end
end

local function send(apt, msg)
  msg.clientkey = clientkey
  if config.debug then
    print(apt.host, apt.port, "send", cjson.encode(msg))
  end
  return apt:send(objectbuf.encode(msg, sym))
end

local function send_any(apt, msg, ...)
  msg.clientkey = clientkey
  -- print("send", cjson.encode(msg))
  return apt:send(objectbuf.encode(msg, sym), ...)
end

function command_map.list(apt, host, port, msg)
  internal_port = serv.serv:getPort()
  -- print(cjson.encode(msg))

  for i,v in ipairs(msg.data) do
    local t = allowed_map[v.host]
    if not t then
      t = {}
      allowed_map[v.host] = t
    end
    t[v.port] = utils.gettime()

    if v.internal_host and v.internal_port then
      local t = allowed_map[v.internal_host]
      if not t then
        t = {}
        allowed_map[v.internal_host] = t
      end
      t[v.internal_port] = utils.gettime()
    end
  end

  for i,v in ipairs(msg.data) do
    -- print("list", i, cjson.encode(v))
    local peer = peer_map[v.clientkey]
    if peer then
      local output_index = send(peer.apt, {type = "ppkeepalive"})
      peer.apt.ppkeepalive_map[output_index] = true
    else
      local apt = serv.getapt(v.host, v.port)
      local output_index = send_any(apt, {type = "ppkeepalive"}, v.host, v.port)
      apt.ppkeepalive_map[output_index] = true

      if v.internal_host and v.internal_port then
        local apt = serv.getapt(v.internal_host, v.internal_port)
        local output_index = send_any(apt, {type = "ppkeepalive"}, v.internal_host, v.internal_port)
        apt.ppkeepalive_map[output_index] = true
      end
    end
    -- if not peer then
    -- print("send ppkeepalive", v.host, v.port)
    -- else
    -- print("ignore nat", v.clientkey, peer)
    -- end
  end
end

function command_map.ppconnect(apt, host, port, msg)
  local peer = peer_map[msg.clientkey]
  local obj

  print(host, port, cjson.encode(msg))

  obj = {
    connkey = msg.connkey,
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
        obj.connected = true
        send(apt, {type = "ppconnected", connkey = msg.connkey})
      end,
      onread = function(buf)
        table.insert(obj.input_queue, buf)
        sync_port()
      end,
      ondisconnected = function(msgstr)
        obj.connected = nil
        print("remote disconnected", msgstr)
        send(apt, {type = "ppdisconnectedmaster", connkey = msg.connkey})
      end
    }
  }

  peer.ppservice_connection_map[msg.connkey] = obj
end

function command_map.ppconnected(apt, host, port, msg)
  print(host, port, cjson.encode(msg))
  local peer = get_peer(apt)
  local obj = peer.ppclient_connection_map[msg.connkey]
  obj.connected = true

  sync_port()
end

function command_map.ppdisconnectedmaster(apt, host, port, msg)
  print(host, port, cjson.encode(msg))
  local peer = get_peer(apt)
  local obj = peer.ppclient_connection_map[msg.connkey]
  peer.ppclient_connection_map[msg.connkey] = nil
  -- clean up client apt.
  if obj then
    obj.connected = nil
    obj.apt:close()
    obj.apt = nil
  end
end

function command_map.ppdisconnectedclient(apt, host, port, msg)
  print(host, port, cjson.encode(msg))
  local peer = get_peer(apt)
  local obj = peer.ppservice_connection_map[msg.connkey]
  -- clean up server conn.
  if obj then
    obj.connected = nil
    peer.ppservice_connection_map[msg.connkey] = nil
    obj.conn:close()
    obj.conn = nil
  end
end

function command_map.ppdata_req(apt, host, port, msg)
  local peer = get_peer(apt)
  local obj = peer.ppservice_connection_map[msg.connkey]
  if obj then
    obj.conn:send(msg.data)
  end

  -- msg.data = nil
  -- print(os.date("%X"), host, port, cjson.encode(msg))
end

function command_map.ppdata_resp(apt, host, port, msg)
  local peer = get_peer(apt)
  local obj = peer.ppclient_connection_map[msg.connkey]
  if obj and obj.connected then
    obj.apt:send(msg.data)
  end

  -- local len = #(msg.data)
  -- msg.data = nil
  -- print(os.date("%X"), host, port, cjson.encode(msg), len)
end

function command_map.ppkeepalive(apt, host, port, msg)
  if config.debug then
    print(os.date("%X"), host, port, cjson.encode(msg))
  end
  local peer = peer_map[msg.clientkey]
  if not peer then
    peer = {
      apt = apt,
      host = host,
      port = port,
      ppservice_connection_map = {},
      ppclient_connection_map = {},
    }

    peer_map[msg.clientkey] = peer
  else
    peer.host = host
    peer.port = port
  end
end

local function list_peers()
  while true do
    send_any(remote_serv, {type = "list", internal_host = internal_host, internal_port = internal_port, internal_netmask = internal_netmask}, REMOTE_HOST, REMOTE_PORT)
    -- send{type = "keepalive"}
    fan.sleep(3)
  end
end

local function keepalive_peers()
  while true do
    sync_port()
    for k,peer in pairs(peer_map) do
      if utils.gettime() - peer.apt.last_keepalive > 10 then
        local output_index = send(peer.apt, {type = "ppkeepalive"})
        peer.apt.ppkeepalive_map[output_index] = true
      end
    end

    for k,peer in pairs(peer_map) do
      if utils.gettime() - peer.apt.last_keepalive > 20 then
        peer.apt:cleanup()
        print(k, "keepalive timeout.")
        for connkey,obj in pairs(peer.ppclient_connection_map) do
          obj.apt:close()
          obj.apt = nil

          local t = bind_map[obj.bind_port]
          if t then
            t.serv:close()
            t.serv = nil
            bind_map[obj.bind_port] = nil
          end
        end

        peer_map[k] = nil

        for k,apt in pairs(serv.clientmap) do
          if apt == peer.apt then
            serv.clientmap[k] = nil
            break
          end
        end

      end
    end

    fan.sleep(5)
  end
end

local function sync_port_buffers()
  while true do
    local count = 0
    for ckey,peer in pairs(peer_map) do
      for connkey,obj in pairs(peer.ppservice_connection_map) do
        if not obj.forward_index and #(obj.input_queue) > 0 then
          local data = table.remove(obj.input_queue, 1)
          -- obj.input_queue = {}
          local auto_index = obj.auto_index + 1
          obj.auto_index = auto_index
          obj.forward_index = send(peer.apt, {
              type = "ppdata_resp",
              connkey = connkey,
              data = data,
              index = auto_index
            })
          if config.debug then
            print("forwarding to client", obj.forward_index, auto_index)
          end
          peer.apt.index_conn_map[obj.forward_index] = obj
          count = count + 1
        end
      end
    end

    for k,peer in pairs(peer_map) do
      for connkey,obj in pairs(peer.ppclient_connection_map) do
        -- print(obj, obj.connected, obj.forward_index, #(obj.input_queue))
        if obj.connected and not obj.forward_index and #(obj.input_queue) > 0 then
          local data = table.remove(obj.input_queue, 1)
          -- obj.input_queue = {}
          local auto_index = obj.auto_index + 1
          obj.auto_index = auto_index
          obj.forward_index = send(peer.apt, {
              type = "ppdata_req",
              connkey = connkey,
              data = data,
              index = auto_index
            })
          if config.debug then
            print("forwarding to server", obj.forward_index, auto_index)
          end
          peer.apt.index_conn_map[obj.forward_index] = obj
          count = count + 1
        end
      end
    end

    sync_port_running = coroutine.running()
    coroutine.yield()
    sync_port_running = nil
  end
end

local function allowed_map_cleanup()
  while true do
    for host,t in pairs(allowed_map) do
      for port,last_alive in pairs(t) do
        if utils.gettime() - last_alive > 30 then
          t[port] = nil
        end
      end
      if not next(t) then
        allowed_map[host] = nil
      end
    end
    fan.sleep(1)
  end
end

local function bind_apt(apt)
  apt.ppkeepalive_map = {}
  apt.index_conn_map = {}
  apt.last_keepalive = 0

  apt.onread = function(body, host, port)
    local msg = objectbuf.decode(body, sym)
    if not msg then
      print("decode failed", host, port, #(body))
    end

    local t = allowed_map[host]
    if not t then
      t = {}
      allowed_map[host] = t
    end
    t[port] = utils.gettime()

    -- print(host, port, cjson.encode(msg))

    local command = command_map[msg.type]
    if command then
      apt.last_keepalive = utils.gettime()
      if msg.clientkey then
        command_map.ppkeepalive(apt, host, port, msg)
      end
      command(apt, host, port, msg)
    end
  end

  apt.onsent = function(index)
    -- print("onsent", apt)
    apt.last_keepalive = utils.gettime()
    local obj = apt.index_conn_map[index]

    if obj then
      obj.forward_index = nil
      sync_port()
    elseif apt.ppkeepalive_map[index] then
      apt.ppkeepalive_map[index] = nil
    end
  end

  apt.ontimeout = function(package, host, port)
    if host and port then
      local alive = allowed_map[host] and allowed_map[host][port]
      if not alive then
        print("timeout, drop", #(package), host, port)
        return false
      else
        local output_index = string.unpack("<I2", package)
        if apt.ppkeepalive_map[output_index] then
          apt.ppkeepalive_map[output_index] = nil
          print("drop ppkeepalive")
          return false
        end
      end
    else
      return true
    end

    return true
  end
end

fan.loop(function()
    serv = connector.bind("udp://0.0.0.0:0")
    remote_serv = serv.getapt(REMOTE_HOST, REMOTE_PORT)
    bind_apt(remote_serv)

    serv.onaccept = function(apt)
      bind_apt(apt)
    end

    coroutine.wrap(list_peers)()
    coroutine.wrap(keepalive_peers)()
    coroutine.wrap(sync_port_buffers)()
    coroutine.wrap(allowed_map_cleanup)()

    local connkey_index = 0

    local httpd = require "fan.httpd"
    debug_console_serv = httpd.bind{
      port = tonumber(arg[2]),
      onService = function(req, resp)
        local params = req.params
        if params.action == "incoming" then
          resp:addheader("Content-Type", "text/plain; charset=UTF-8")
          resp:reply_start(200, "OK")
          resp:reply_chunk(string.format("udp send: %d, receive: %d, resend: %d\n",
              config.udp_send_total, config.udp_receive_total, config.udp_resend_total))
          for key,apt in pairs(serv.clientmap) do
            if apt.last_keepalive > 0 then
              resp:reply_chunk(string.format("%s(%1.3f)\twaiting: %d, ack total: %d\n", key, utils.gettime() - apt.last_keepalive, apt._output_wait_count, apt.output_wait_ack_total))
              resp:reply_chunk("----------\n")
              local incoming = apt._incoming_map[key]
              if incoming then
                for output_index,incoming_object in pairs(incoming) do
                  if incoming_object.done then
                    resp:reply_chunk(string.format("%06d\treceived %d\n", output_index, incoming_object.count))
                  else
                    local count = 0
                    for idx,body in pairs(incoming_object.items) do
                      if body then
                        count = count + 1
                      end
                    end

                    resp:reply_chunk(string.format("%06d\treceiving %d/%d\n", output_index, count, incoming_object.count))
                  end
                end
              end

              collectgarbage()
              resp:reply_chunk("\n")
            end
          end
          resp:reply_chunk(string.format("\nMem: %1.3f\n", collectgarbage("count")))
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

            serv = tcpd.bind{
              port = port,
              onaccept = function(apt)
                local d = {
                  input_queue = {},
                  apt = apt,
                  bind_port = port,
                  peer = peer,
                  host = peer.host,
                  port = peer.port,
                  forward_index = nil,
                  auto_index = 0,
                  connected = true,
                }

                connkey_index = connkey_index + 1
                d.connkey = connkey_index
                peer.ppclient_connection_map[d.connkey] = d

                send(peer.apt, {
                    type = "ppconnect",
                    connkey = d.connkey,
                    host = params.remote_host,
                    port = params.remote_port
                  })

                apt:bind{
                  onread = function(buf)
                    table.insert(d.input_queue, buf)

                    sync_port()
                  end,
                  ondisconnected = function(msg)
                    print("client disconnected", msg)
                    d.connected = nil
                    send(peer.apt, {type = "ppdisconnectedclient", connkey = d.connkey})
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
