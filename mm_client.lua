local sqlite3 = require "lsqlite3"
local orm = require "sqlite3.ormlite"
local remote_url = "https://mm.youchat.me"
local fan = require "fan"
local http = require "fan.http"
local cjson = require "cjson"
local lpeg = require "lpeg"

require "compat53"

local db = sqlite3.open("mm.db")

local setting_model = {
    ["key"] = "text",
    ["value"] = "text",
}
local task_model = {
    ["path"] = "text",
    ["temppath"] = "text",
    ["name"] = "text",
    ["md5"] = "text",
    ["size"] = "integer",
    ["status"] = "integer default 0"
}

local STATUS_INVALID = -1

local block_model = {
    ["taskid"] = "integer",
    ["beginoffset"] = "integer default 0",
    ["endoffset"] = "integer default 0",
    ["offset"] = "integer default 0",
}

local context = orm.new(db, {
    ["setting"] = setting_model,
    ["task"] = task_model,
    ["block"] = block_model
})

local function split(s, sep)
  sep = lpeg.P(sep)
  local elem = lpeg.C((1 - sep)^0)
  local p = lpeg.Ct(elem * (sep * elem)^0)   -- make a table capture
  return lpeg.match(p, s)
end

local function escape_path(path)
    local parts = split(path, "/")
    local t = {}
    for i,v in ipairs(parts) do
        table.insert(t, http.escape(v))
    end
    return table.concat(t, "/")
end

local function listfiles(path, session)
    local url = string.format("%s%s?session=%s", remote_url, escape_path(path), session)
    local ret = http.get{
        url = url
    }

    if ret.responseCode == 200 and not ret.error then
        local map = cjson.decode(ret.body)
        if map.success then
            return map.list
        end
    end
    print(url, ret.body)
end

local function listfilelinks(path, session)
    local url = string.format("%s%s?session=%s", remote_url, escape_path(path), session)
    local ret = http.get{
        url = url
    }

    if ret.responseCode == 200 and not ret.error then
        local map = cjson.decode(ret.body)
        if map.success then
            return map.list
        end
    end
    print(url, ret.body)
end

local function addtask(path, session)
    local list = listfiles(path, session)
    if list then
        for i,v in ipairs(list) do
            if v.isdir then
                addtask(v.path, session)
            else
                local task = context.task("one", "where path=?", v.path)
                if not task then
                    task = context.task("new", {
                        path = v.path,
                        name = string.match(v.path, ".*([^/]+)"),
                        size = v.size,
                        md5 = v.md5,
                    })
                end
            end
        end
    end
end

local function main()
    local session = context.setting("one", "where key=?", "session")
    if not session then
        local ret = http.post{
            url = string.format("%s/bind", remote_url),
            body = "",
        }
        if ret.responseCode == 200 and not ret.error then
            local map = cjson.decode(ret.body)
            context.setting("new", {
                key = "session",
                value = map.session
            })
            print("bindcode", map.code)
        else
            for k,v in pairs(ret) do
                print(k,v)
            end
        end

        os.exit(0)
    end

    -- addtask("/file", session.value)
    local total = 0
    context.task(function(r)
        -- local links = listfilelinks(r.path, session.value)
        -- if links and #(links) == 1 and string.find(links[1], "/wenxintishi-", 1, true) then
        --     r.status = STATUS_INVALID
        --     r:update()
        -- end
        -- return true
        total = total + r.size
        local gb = r.size/1024/1024/1024
        if gb > 0.1 then
            print(gb, r.path)
        end
    end, "where status=-1") -- 
    print(total/1024/1024/1024)
end

fan.loop(main)
