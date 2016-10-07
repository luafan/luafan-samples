local json = require "cjson"
local fan = require "fan"
local http = require "fan.http"
local io = io
local pairs = pairs
local string = string
local setmetatable = setmetatable
local table = table

local total_piece_count = 10
local minum_piece_length = 512 * 1024

local task_mt = {}
task_mt.__index = task_mt

local tasks = {}

local function gettime()
    local sec,usec = fan.gettime()
    return sec + usec / 1000000.0
end

local function random_url(task)
    if task.peerurls then
        return task.peerurls[math.random(#(task.peerurls))]
    else
        return task.url
    end
end

local function start_task(task, beginoffset, endoffset, offset)
    if not offset then
        offset = beginoffset
    end

    local subtask = {name = string.format("task%02d", task.nameindex), beginoffset = beginoffset, endoffset = endoffset, offset = offset or beginoffset, complete = false}
    task.nameindex = task.nameindex + 1
    task.subtasks[subtask.name] = subtask

    local url = random_url(task)
    -- print("using", url)
    local req = {
        url = url,
        headers = {
            ["Range"] = endoffset and string.format("bytes=%d-%d", offset, endoffset) or string.format("bytes=%d-", offset)
        },
        timeout = 30,
        onreceive = function(data)
            if task.stop then
                return 0
            end

            task.f:seek("set", subtask.offset)
            task.f:write(data)
            subtask.offset = subtask.offset + #(data)
            task.current_downloaded = task.current_downloaded + #(data)

            if subtask.endoffset and subtask.offset > subtask.endoffset then
                return 0 -- abort download
            end
        end,
        onheader = function(header)
            if header.responseCode == 206 then
                for k,v in pairs(header) do
                    if k:lower() == "content-length" then
                        if not subtask.endoffset then
                            subtask.endoffset = tonumber(v)
                        end
                    elseif k:lower() == "content-range" then
                        local offset,total = string.match(v, "bytes (%d+)[-]%d+/(%d+)")
                        subtask.offset = tonumber(offset)
                        task.length = tonumber(total)
                    end
                end
            elseif header.responseCode == 302 then
                task.url = header.Location
            elseif header.responseCode == 200 then
                task.offset = 0
            else
                print(header.responseCode)
                task.stop = true
            end
        end,
        oncomplete = function(ret)
            subtask.complete = true
            subtask.ret = ret
        end
    }

    http.get(req)
end

function task_mt:start()
    if self.stop then
        local started = false
        local info = io.open(string.format("%s.json", self.path), "rb")
        if info then
            local data = info:read("*all")
            local task = json.decode(data)
            info:close()

            if task.completed then
                return
            end

            if task.length then
                self.length = task.length
            end

            self.url = task.url

            self.stop = false
            self.subtasks = {}
           for _,v in pairs(task.subtasks) do
                start_task(self, v.beginoffset, v.endoffset, v.offset)
                started = true
            end
        end

        if not started then
            self.stop = false
            start_task(self, 0, nil)
        end
    else
        return
    end
end

function task_mt:save()
    if self.f then
        self.f:flush()
    end
    local info = assert(io.open(string.format("%s.json", self.path), "wb"))
    info:write(json.encode{subtasks = self.subtasks, length = self.length, url = self.url})
    info:close()
end

function task_mt:stop()
    self.stop = true
    self:save()
end

local function format_time(t)
    local min = math.floor(t / 60)
    local sec = math.floor(t) % 60
    return string.format("%02d:%02d", min, sec)
end

function task_mt:info()
    local unfinished = 0

    local peercount = 0

    for _,v in pairs(self.subtasks) do
        if v.endoffset then
            unfinished = unfinished + (v.endoffset - v.offset)
        end
        peercount = peercount + 1
    end

    return {
        progress = self.length and (self.length - unfinished) / self.length * 100 or 0,
        peercount = peercount,
        speed = self.speed,
        length = self.length,
        unfinished = unfinished,
        estimate = (self.length and self.speed > 0) and format_time(unfinished / self.speed) or "N/A"
    }

end

function task_mt:lifecycle()
    if self.completed or self.stop then
        return
    end

    local sec = gettime()

    if sec - self.last_mark_time >= 2 then
        self.speed = (self.current_downloaded - self.last_mark_value) / (sec - self.last_mark_time)
        self.last_mark_time = sec
        self.last_mark_value = self.current_downloaded
    end

    local allcomplete = true
    local completed = {}
    local restartneed = {}
    local subtasks = self.subtasks

    local taskcount = 0

    for k,v in pairs(subtasks) do
        if v.complete then
            if not v.endoffset or v.offset < v.endoffset then
                table.insert(restartneed, v)
                taskcount = taskcount + 1
            end
            table.insert(completed, k)
        else
            taskcount = taskcount + 1
        end
    end

    for _,v in ipairs(completed) do
        subtasks[v] = nil
    end

    for _,v in ipairs(restartneed) do
        start_task(self, v.beginoffset, v.endoffset, v.offset)
    end

    while taskcount < total_piece_count do
        local maxtask = nil
        local maxleft = 0

        for k,v in pairs(subtasks) do
            if v.endoffset then
                local left = v.endoffset - v.offset
                if left > maxleft then
                    maxleft = left
                    maxtask = v
                end                    
            end
        end

        if maxtask and maxleft > minum_piece_length then
            local center = maxtask.offset + math.floor(maxleft / 2)
            start_task(self, center, maxtask.endoffset)
            maxtask.endoffset = center
            taskcount = taskcount + 1
        else
            break
        end
    end

    if self.length and taskcount == 0 then
        self.f:close()
        self.f = nil
        self.completed = true
    end
end

local function add(url, path, peerurls)
    for i,v in ipairs(tasks) do
        if v.url == url then
            return v
        end
    end

    local task = {url = url, peerurls = peerurls, path = path, subtasks = {}, current_downloaded = 0, speed = 0, last_mark_time = gettime(), last_mark_value = 0, stop = true, completed = false, nameindex = 1}
    local f = io.open(path, "rb+")
    if not f then
        f = io.open(path, "wb")
    end
    task.f = f
    
    setmetatable(task, task_mt)
    table.insert(tasks, task)

    return task
end

local function list()
    return tasks
end

return {
    add = add,
    list = list,
    pause = pause,
    resume = resume,
}