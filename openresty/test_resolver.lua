package.cpath = "/usr/local/lib/?.so;" .. package.cpath

local fan = require "fan"
ngx = require "ngx"

-- test case from https://github.com/openresty/lua-resty-dns
-- ipv6 not ready as ngx.re.sub not implemented.

local function main_resolver()
    local resolver = require "resty.dns.resolver"
    local r, err = resolver:new{
        nameservers = {"114.114.114.114" }, -- , {"8.8.8.8", 53}
        retrans = 5,  -- 5 retransmissions on receive timeout
        timeout = 2000,  -- 2 sec
    }

    if not r then
        ngx.say("failed to instantiate the resolver: ", err)
        return
    end

    local answers, err = r:query("api.marykayintouch.com.cn")
    if not answers then
        ngx.say("failed to query the DNS server: ", err)
        return
    end

    if answers.errcode then
        ngx.say("server returned error code: ", answers.errcode,
                ": ", answers.errstr)
    end

    for i, ans in ipairs(answers) do
        ngx.say(ans.name, " ", ans.address or ans.cname,
                " type:", ans.type, " class:", ans.class,
                " ttl:", ans.ttl)
    end

    os.exit()
end

fan.loop(main_resolver)
