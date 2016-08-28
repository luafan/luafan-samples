local fan = require "fan"
local http = require "fan.http"
local tcpd = require "fan.tcpd"
local udpd = require "fan.udpd"

local setmetatable = setmetatable
local coroutine = coroutine
local tonumber = tonumber
local type = type
local table = table

local sha1 = require 'sha1' -- luarocks/lmd5 (this will break luarocks, so remove it before other module installed complete.)
local base64 = require "base64" -- luarocks/base64

------------ tcp bgn ------------
local tcp_mt = {}
tcp_mt.__index = tcp_mt

function tcp_mt:settimeout(timeout)
    self.timeout = timeout
end

function tcp_mt:connect(host, port)
    self.host = host
    self.port = port
    self.connected = false

    local running = coroutine.running()

    self.conn = tcpd.connect{
        host = host,
        port = port,
        read_timeout = self.timeout,
        write_timeout = self.timeout,
        onconnected = function()
            self.connected = true
            coroutine.resume(running, true)
        end,
        onsendready = function()
            if self.onsendready_co then
                coroutine.resume(self.onsendready_co, #(self.send_data))
                self.onsendready_co = nil
                self.send_data = nil
            end
        end,
        onread = function(buf)
            self.cache = self.cache and (self.cache .. buf) or buf

            if self.readx_co then
                coroutine.resume(self.readx_co)
            end
        end,
        ondisconnected = function(msg)
            self.connected = false
            self.message = msg
        end
    }

    return coroutine.yield()
end

function tcp_mt:send(data)
    if not self.connected then
        return nil, self.message
    end

    self.send_data = data
    self.onsendready_co = coroutine.running()
    self.conn:send(data)

    return coroutine.yield()
end

function tcp_mt:readline()
    while true do
        if self.cache then
            local st,ed = string.find(self.cache, "\r\n", 1, true)
            if st and ed then
                data = string.sub(self.cache, 1, st - 1)
                if #(self.cache) > ed then
                    self.cache = string.sub(self.cache, ed + 1)
                else
                    self.cache = nil
                end
                return data
            else
                self.readx_co = coroutine.running()
                coroutine.yield()
            end
        else
            self.readx_co = coroutine.running()
            coroutine.yield()
        end
    end
end

function tcp_mt:readlen(len)
    while true do
        if self.cache then
            if #(self.cache) == len or self.udp then
                local data = self.cache
                self.cache = nil
                return data
            elseif #(self.cache) > len then
                local data = string.sub(self.cache, 1, len)
                self.cache = string.sub(self.cache, len + 1)
                return data
            else
                self.readx_co = coroutine.running()
                coroutine.yield()
            end
        else
            self.readx_co = coroutine.running()
            coroutine.yield()
        end
    end
end

function tcp_mt:readall()
    while true do
        if self.cache then
            local data = self.cache
            self.cache = nil
            return data
        else
            self.readx_co = coroutine.running()
            coroutine.yield()
        end
    end
end

function tcp_mt:receive(optlen)
    if not self.connected then
        return nil, self.message
    end

    if optlen then
        local numlen = tonumber(optlen)
        if numlen then
            return self:readlen(numlen)
        elseif type(optlen) == "string" then
            if #(optlen) ~= 2 or string.sub(optlen, 1, 1) ~= "*" then
                error("bad pattern argument: " .. optlen)
            else
                local code = string.sub(optlen, 2, 2)
                if code == "l" then
                    return self:readline()
                elseif code == "a" then
                    return self:readall()
                else
                    error("bad pattern argument: " .. optlen)
                end
            end
            return self:readline()
        else
            error("bad pattern argument: ", optlen)
        end
    else
        return self:readline()
    end
end

function tcp_mt:getreusedtimes()
    return 0
end

function tcp_mt:setkeepalive(...)
    return true
end

local function socket_tcp_new()
    local obj = {}

    obj.message = nil
    obj.onsendready = nil
    obj.onread = nil
    obj.cache = nil

    setmetatable(obj, tcp_mt)
    return obj
end

------------ tcp end ------------

------------ udp bgn ------------
local udp_mt = {}
udp_mt.__index = udp_mt

udp_mt.receive = tcp_mt.receive
udp_mt.readline = tcp_mt.readline
udp_mt.readlen = tcp_mt.readlen

function udp_mt:setpeername(host, port)
    self.host = host
    self.port = port

    self.conn = udpd.new{
        host = host,
        port = port,
        onsendready = function()
            local count = 0
            while #(self.sendqueue) > 0 do
                local query = table.remove(self.sendqueue)
                count = count + #(query)
                self.conn:send(query)
            end

            if self.onsendready_co then
                coroutine.resume(self.onsendready_co, count)
                self.onsendready_co = nil
            end
        end,
        onread = function(buf)
            self.cache = self.cache and (self.cache .. buf) or buf

            if self.readx_co then
                coroutine.resume(self.readx_co)
            end
        end,
    }

    self.connected = true

    return true
end

function udp_mt:send(query)
    if type(query) == "table" then
        query = table.concat(query)
    elseif type(query) ~= "string" then
        return nil, "only accept string or table list of string"
    end

    table.insert(self.sendqueue, query)

    self.onsendready_co = coroutine.running()
    self.conn:send_req()
    return coroutine.yield()
end

function udp_mt:settimeout()
    print("set timeout N/I")
end

local function socket_udp_new()
    local obj = {sendqueue = {}, udp = true}
    setmetatable(obj, udp_mt)
    return obj
end
------------ udp end ------------

local ngx_socket = {
    tcp = socket_tcp_new,
    udp = socket_udp_new
}

local function ngx_say(...)
    print(...)
end

local function ngx_log(...)
    print(...)
end

local function ngx_exit(...)
    os.exit(...)
end

local function sha1_bin(data)
    local d = sha1.new()
    d:update(data)
    return d:digest(true)
end

local socket_mt = {}
socket_mt.__index = socket_mt

local ngx_req_mt = {
    __index = function(t, k)
        if k == "read_body" then
            return t.ctx.read_body
        else
            return ngx_req[k]
        end
    end
}

local ngx_obj = {
    escape_uri = http.escape,
    unescape_uri = http.unescape,
    encode_base64 = base64.encode,
    sha1_bin = sha1_bin,
    say = ngx_say,
    log = ngx_log,
    exit = ngx_exit,
    socket = ngx_socket,
    INFO = "[INFO]",
    ERR = "[ERRO]",
    config = {
        ngx_lua_version = 9011,
    },
    time = function()
        local sec,usec = fan.gettime()
        return sec + usec / 1000000
    end,
    re = {
        sub = function() error("not implemented") end
    },
}

local ngx_obj_mt = {
    __index = function(t, k)
        if k == "header" then
            return t.ctx.resp_headers
        else
            return ngx_obj[k]
        end
    end
}

local function ngx_obj_new(ctx)
    local ngx_req_obj = {ctx = ctx, read_body = ctx.read_body}
    ngx_req_obj.http_version = ctx.http_ver
    ngx_req_obj.get_headers = function()
        return ctx.req_headers
    end

    ngx_req_obj.socket = function()
        local self = {conn = ctx.apt, connected = true}
        setmetatable(self, tcp_mt)

        ctx.callbacks.onsendready = function()
            if self.onsendready_co then
                coroutine.resume(self.onsendready_co, #(self.send_data))
                self.onsendready_co = nil
                self.send_data = nil
            end
        end
        
        ctx.callbacks.onread = function(buf)
            -- print("onread", buf)
            self.cache = self.cache and (self.cache .. buf) or buf

            if self.readx_co then
                coroutine.resume(self.readx_co)
            end
        end

        ctx.callbacks.ondisconnected = function(msg)
            self.connected = false
            self.message = msg
        end

        return self
    end

    local obj = {ctx = ctx, req = ngx_req_obj, header = {}}
    obj.send_headers = function()
        local list = {}
        table.insert(list, string.format("HTTP/1.1 %d Switching Protocols", obj.status or 200))
        for k,v in pairs(obj.header) do
            table.insert(list, string.format("%s: %s", k, v))
        end
        table.insert(list, "")
        table.insert(list, "")
        ctx.apt:send(table.concat(list, "\r\n"))
        obj.headers_sent = true
        return true
    end
    obj.flush = function()
        return true
    end
    setmetatable(obj, ngx_obj_mt)
    return obj
end

ngx_obj.new = ngx_obj_new

return ngx_obj