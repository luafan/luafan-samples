package.cpath = "/usr/local/lib/?.so;" .. package.cpath

local fan = require "fan"
ngx = require "ngx"

local memcached = require "resty.memcached"

-- test case from https://github.com/openresty/lua-resty-memcached
local function main_memc()
    local memc, err = memcached:new()
    memc:set_timeout(1000)

    local ok, err = memc:connect("127.0.0.1", 11211)
    if not ok then
        ngx.say("failed to connect: ", err)
        return
    end

    local ok, err = memc:flush_all()
    if not ok then
        ngx.say("failed to flush all: ", err)
        return
    end

    local ok, err = memc:set("dog", 32)
    if not ok then
        ngx.say("failed to set dog: ", err)
        return
    end

    local res, flags, err = memc:get("dog")
    if err then
        ngx.say("failed to get dog: ", err)
        return
    end

    if not res then
        ngx.say("dog not found")
        return
    end

    ngx.say("dog: ", res)

    -- put it into the connection pool of size 100,
    -- with 10 seconds max idle timeout
    local ok, err = memc:set_keepalive(10000, 100)
    if not ok then
        ngx.say("cannot set keepalive: ", err)
        return
    end
end

main_co = coroutine.create(main_memc)
print(coroutine.resume(main_co))

fan.loop()
