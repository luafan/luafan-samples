
local fan = require "fan"
local tcpd = require "fan.tcpd"

--[[
http://yourip:8888/ get the list of tunnels

Proxy yourip:8888 support CONNECT only.
]]

local tunnels = {}

local function onaccept(apt)
    local cache = nil

    local method
    local path
    local version
    local headers = {}

    local first_line = false
    local header_complete = false
    local accepted = false
    local disconnected = false

    local conn
    local conn_connected = false

    local readline = function()
        if cache then
            local st,ed = string.find(cache, "\r\n", 1, true)
            if not st or not ed then
                st,ed = string.find(cache, "\n", 1, true)
            end
            if st and ed then
                data = string.sub(cache, 1, st - 1)
                if #(cache) > ed then
                    cache = string.sub(cache, ed + 1)
                else
                    cache = nil
                end
                return data
            end
        end
    end

    local readheader = function()
        while not header_complete do
            local line = readline()
            if not line then
                break
            else
                if #(line) == 0 then
                    header_complete = true
                else
                    if first_line then
                        local k,v = string.match(line, "([^:]+):[ ]*(.*)")
                        k = string.lower(k)
                        local old = headers[k]
                        if old then
                            if type(old) == "table" then
                                table.insert(old, v)
                            else
                                headers[k] = {old, v}
                            end
                        else
                            headers[k] = v
                        end
                    else
                        method,path,version = string.match(line, "([A-Z]+) ([^ ]+) HTTP/([0-9.]+)")
                        first_line = true
                    end
                end
            end
        end
    end

    local info = apt:remoteinfo()

    apt:bind{
        onread = function(buf)
            if conn then
                if conn_connected then
                    conn:send(buf)
                    apt:pause_read()
                    -- print(path, "send", #(buf))
                else
                    cache = cache and (cache .. buf) or buf
                end
                return
            end

            cache = cache and (cache .. buf) or buf
            if not header_complete then
                readheader()
            end

            if header_complete then
                if method == "CONNECT" and not conn then
                    if not accepted then
                        accepted = true
                        -- print(info.ip, path, "accept")
                        tunnels[apt] = path
                        apt:send("HTTP/1.1 200 Connection Established\r\n\r\n")
                    end

                    local host,port = string.match(path, "([^:]+):(%d+)")
                    conn = tcpd.connect{
                        host = host,
                        port = tonumber(port),
                        onconnected = function()
                            -- print(path, "onconnected")
                            conn_connected = true
                            if cache then
                                conn:send(cache)
                                apt:pause_read()
                                -- print(path, "send", #(cache))
                                cache = nil
                            end
                        end,
                        onsendready = function()
                            apt:resume_read()
                        end,
                        onread = function(buf)
                            -- print(path, "read", #(buf))
                            apt:send(buf)
                        end,
                        ondisconnected = function(msg)
                            -- print(path, msg)
                            tunnels[apt] = nil
                            apt:close()
                        end
                    }
                elseif method == "GET" then
                    local list = {}
                    for k,v in pairs(tunnels) do
                        table.insert(list, v)
                    end
                    local body = table.concat(list, "\n")
                    apt:send(string.format("HTTP/1.0 200 OK\r\nConnection: close\r\nContent-Type: text/plain\r\nContent-Length: %d\r\n\r\n%s", #(body), body))
                end
            end
        end,
        ondisconnected = function(msg)
            -- print(info.ip, msg)
            tunnels[apt] = nil
            if conn then
                conn:close()
            end
        end
    }
end

local function main()
    serv = tcpd.bind{
        port = 8888,
        onaccept = onaccept,
    }
end

fan.loop(main)