package.cpath = "/usr/local/lib/?.so;" .. package.cpath

local fan = require "fan"
ngx = require "ngx"

-- test case from https://github.com/openresty/lua-resty-websocket
local function websocket_func(ngx)
    local server = require "resty.websocket.server"

    local wb, err = server:new{
        timeout = 5000,  -- in milliseconds
        max_payload_len = 65535,
        ngx = ngx
    }
    if not wb then
        ngx.log(ngx.ERR, "failed to new websocket: ", err)
        return ngx.exit(444)
    end

    local data, typ, err = wb:recv_frame()

    if not data then
        ngx.log(ngx.ERR, "failed to receive a frame: ", err)
        return ngx.exit(444)
    end

    if typ == "close" then
        -- send a close frame back:

        local bytes, err = wb:send_close(1000, "enough, enough!")
        if not bytes then
            ngx.log(ngx.ERR, "failed to send the close frame: ", err)
            return
        end
        local code = err
        ngx.log(ngx.INFO, "closing with status code ", code, " and message ", data)
        return
    end

    if typ == "ping" then
        -- send a pong frame back:

        local bytes, err = wb:send_pong(data)
        if not bytes then
            ngx.log(ngx.ERR, "failed to send frame: ", err)
            return
        end
    elseif typ == "pong" then
        -- just discard the incoming pong frame

    else
        ngx.log(ngx.INFO, "received a frame of type ", typ, " and payload ", data)
    end

    wb:set_timeout(1000)  -- change the network timeout to 1 second

    bytes, err = wb:send_text("Hello world")
    if not bytes then
        ngx.log(ngx.ERR, "failed to send a text frame: ", err)
        return ngx.exit(444)
    end

    bytes, err = wb:send_binary("blah blah blah...")
    if not bytes then
        ngx.log(ngx.ERR, "failed to send a binary frame: ", err)
        return ngx.exit(444)
    end

    local bytes, err = wb:send_close(1000, "enough, enough!")
    if not bytes then
        ngx.log(ngx.ERR, "failed to send the close frame: ", err)
        return
    end
end

local function main_websocket()
    local find_global_mt = {__index = _G}
    conn,port = tcpd.bind{
        port = 9090,
        onaccept = function(apt)
            local cache = nil
            
            local method
            local path
            local version
            local headers = {}

            local first_line = false
            local header_complete = false
            local disconnected = false

            local ws_started = false

            local callbacks = {}

            local env = {
                read_body = function()
                    local data = cache
                    cache = nil
                    return cache
                end,
                http_ver = function()
                    return tonumber(version)
                end,
                req_headers = headers,
                resp_headers = {},
                apt = apt,
                callbacks = callbacks,
            }

            env.ngx = ngx.new(env)

            setmetatable(env, find_global_mt)

            local readline = function()
                if cache then
                    local st,ed = string.find(cache, "\r\n", 1, true)
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

            apt:bind{
                onsendready = function()
                    if callbacks and callbacks.onsendready then
                        callbacks.onsendready()
                    end
                end,
                onread = function(buf)
                    -- print("onread", buf)
                    if not header_complete then
                        cache = cache and (cache .. buf) or buf
                        while not header_complete do
                            local line = readline()
                            if not line then
                                break
                            else
                                if #(line) == 0 then
                                    -- assert(first_line)
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

                    if not ws_started then
                        ws_started = true
                        websocket_func(env.ngx)
                    end

                    if callbacks and callbacks.onread then
                        callbacks.onread(cache and (cache .. buf) or buf)
                        cache = nil
                    end
                end,
                ondisconnected = function(msg)
                    disconnected = true
                    if callbacks and callbacks.ondisconnected then
                        callbacks.ondisconnected(msg)
                    end
                end
            }
        end
    }

    print(conn, port)
end

main_co = coroutine.create(main_websocket)
print(coroutine.resume(main_co))

fan.loop()
