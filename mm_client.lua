local rootPath = "sync"

local remotePath = "/file"
local remote_url = "https://mm.youchat.me"

local MAX_DOWNLOAD_COUNT = 10
local MAX_PEER_COUNT = 10
local PEER_CACHE_SIZE_WATERMARK = 1024 * 512

local BUF_SIZE = 1024 * 1024

local fan = require "fan"
local worker = require "fan.worker"
local md5 = require "md5"

local file_map = {}

local commander = worker.new({
    ["getfilemd5"] = function(path)
      local f = io.open(path, "rb")
      if f then
        local d = md5.new()
        while true do
          local buf = f:read(BUF_SIZE)
          if not buf then
            break
          else
            d:update(buf)
          end
        end
        f:close()

        return d:digest()
      else
        return nil
      end
    end,
    ["pathwrite"] = function(path, offset, buf)
      local f = file_map[path]
      if not f then
        f = io.open(path, "rb+")
        if not f then
          f = io.open(path, "wb")
        end
        file_map[path] = f
      end

      f:seek("set", offset)
      f:write(buf)
    end,
    ["pathflush"] = function(path)
      local f = file_map[path]
      if f then
        f:flush()
      end
    end,
    ["pathclose"] = function(path)
      local f = file_map[path]
      if f then
        f:close()
        file_map[path] = nil
      end
    end,
  }, 1, 1)

require "compat53"

local sqlite3 = require "lsqlite3"
local orm = require "sqlite3.orm"
local http = require "fan.http"
local cjson = require "cjson"
local lpeg = require "lpeg"
local lfs = require "lfs"

local io = io
local pairs = pairs
local string = string
local setmetatable = setmetatable
local table = table

local mkdir_cache = {}

local function split(s, sep)
  sep = lpeg.P(sep)
  local elem = lpeg.C((1 - sep)^0)
  local p = lpeg.Ct(elem * (sep * elem)^0) -- make a table capture
  return lpeg.match(p, s)
end

local function mkdir(path)
  if mkdir_cache[path] then
    return
  else
    mkdir_cache[path] = true
    lfs.mkdir(path)
  end
end

local function mkdirs(path)
  local parts = split(path, "/")
  local t = {}

  for i,v in ipairs(parts) do
    table.insert(t, v)
    mkdir(table.concat(t, "/"))
  end
end

mkdirs(rootPath)

local db = sqlite3.open(string.format("%s/.mm.db", rootPath))

local download_queue_co
local exist_on_complete

local setting_model = {
  ["key"] = "text",
  ["value"] = "text",
}
local task_model = {
  ["path"] = "text",
  ["parentpath"] = "text",
  ["temppath"] = "text",
  ["name"] = "text",
  ["md5"] = "text",
  ["size"] = "integer",
  ["mtime"] = "integer",
  ["ctime"] = "integer",
  ["isdir"] = "integer",
  ["completed"] = "integer default 0",
  ["verified"] = "integer default 0",
  ["lastfailedmd5"] = "text",
  ["exist"] = "integer default 1",
  ["status"] = "integer default 0",
}

-- CREATE INDEX task_path_index on task(path);
-- CREATE INDEX task_parentpath_index on task(parentpath);

local STATUS_INVALID = -1

local block_model = {
  ["taskid"] = "integer",
  ["beginoffset"] = "integer default 0",
  ["endoffset"] = "integer default 0",
  ["offset"] = "integer default 0",
}

local session_value

local context = orm.new(db, {
    ["setting"] = setting_model,
    ["task"] = task_model,
    ["block"] = block_model
  })

local function escape_path(path)
  local parts = split(path, "/")
  local t = {}
  for i,v in ipairs(parts) do
    table.insert(t, http.escape(v))
  end
  return table.concat(t, "/")
end

local function getfilepath(urlpath)
  local path,name = string.match(urlpath, "/file(.*)/([^/]+)")
  local localpath = string.format("%s%s", rootPath, path)
  mkdirs(localpath)
  return string.format("%s/%s", localpath, name)
end

local function is_invalidate_links(links)
  -- http://bcscdn.baidu.com/issue/netdisk/wenxintishi/%e6%b8%a9%e9%a6%a8%e6%8f%90%e7%a4%ba.avi?response-content-disposition=attachment;%20filename=%e6%b8%a9%e9%a6%a8%e6%8f%90%e7%a4%ba.avi
  return not links or #(links) == 0 or (#(links) == 1 and string.find(links[1], "/issue/netdisk/wenxintishi/", 1, true))
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
  print("get", url)
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

local function listdiff(cursor)
  local url = string.format("%s/diff?session=%s&cursor=%s", remote_url, session_value, cursor or "null")
  local ret = http.get{
    url = url
  }

  if ret.responseCode == 200 and not ret.error then
    local map = cjson.decode(ret.body)
    if map.success then
      print(string.format("%d\thas_more=%s\treset=%s", #(map.list), map.has_more, map.reset))
      print(map.list[1] and cjson.encode(map.list[1]))
      return map.list,map.has_more,map.reset,map.cursor
    end
  end
  print(url, ret.body)
end

-----download start ---
local minum_piece_length = 512 * 1024

local task_mt = {}
task_mt.__index = task_mt

local tasks = {}

local function gettime()
  local sec,usec = fan.gettime()
  return sec + usec / 1000000.0
end

local function start_task(task, block)
  if not block then
    block = context.block("new", {
        beginoffset = 0,
        endoffset = task.length,
        offset = 0,
        taskid = task.taskid,
      })

    task.blocks[block.id] = block
  end

  block.complete = false
  local peercache = {}
  local peercache_size = 0

  local peer_flush = function()
    if peercache_size > 0 then
      local oldoffset = block.offset
      local data = table.concat(peercache)
      block.offset = block.offset + peercache_size
      peercache_size = 0
      peercache = {}

      commander:pathwrite(task.path, oldoffset, data)
    end
  end

  local url = task.peerurls[math.random(#(task.peerurls))]
  -- print(url)
  -- print(block.endoffset and string.format("bytes=%1.0f-%1.0f", block.offset, block.endoffset) or string.format("bytes=%1.0f-", block.offset))

  local req = {
    url = url,
    -- verbose = 1,
    ssl_verifyhost = 0,
    ssl_verifypeer = 0,
    headers = {
      ["Range"] = block.endoffset and string.format("bytes=%1.0f-%1.0f", block.offset, block.endoffset) or string.format("bytes=%1.0f-", block.offset)
    },
    timeout = 30,
    onreceive = function(data)
      if task.stop then
        -- print("task stop, abort")
        return 0
      end

      if block.complete or (block.endoffset and block.offset > block.endoffset) then
        -- print("block completed, abort", block.complete, block.offset, block.endoffset)
        return 0 -- abort download
      end

      if not block.complete then
        local data_size = #(data)
        table.insert(peercache, data)
        peercache_size = peercache_size + data_size
        task.current_downloaded = task.current_downloaded + data_size

        if peercache_size < PEER_CACHE_SIZE_WATERMARK then
          return data_size
        else
          peer_flush()
        end
      end
    end,
    onheader = function(header)
      if header.responseCode == 206 then
        for k,v in pairs(header) do
          if k:lower() == "content-length" then
            if not block.endoffset then
              block.endoffset = tonumber(v)
            end
          elseif k:lower() == "content-range" then
            local offset,total = string.match(v, "bytes (%d+)[-]%d+/(%d+)")
            block.offset = tonumber(offset)
            task.length = tonumber(total)
          end
        end
        task.partable = true
      elseif header.responseCode == 302 then
        local location
        for k,v in pairs(header) do
          if k:lower() == "location" then
            location = v
            break
          end
        end
        for i,v in ipairs(task.peerurls) do
          if v == url then
            table.remove(task.peerurls, i)
            break
          end
        end

        local exist = false

        for i,v in ipairs(task.peerurls) do
          if v == location then
            exist = true
            break
          end
        end

        if not exist then
          table.insert(task.peerurls, location)
        end

        -- print("302", location)
        block.complete = true
      elseif header.responseCode == 200 then
        task.partable = false
        task.offset = 0
      else
        -- print(url, "unexpect responsecode:", header.responseCode)
        task.partable = false
        block.complete = true
      end
    end,
    oncomplete = function(ret)
      -- if ret.error then
      -- print("oncomplete error:", ret.error)
      -- end
      peer_flush()
      block.complete = true
      block.ret = ret
      -- print("oncomplete")
    end
  }

  http.get(req)
end

function task_mt:start()
  if self.stop then
    local started = false
    local task = context.task("one", "where id=?", self.taskid)
    if task.completed == 1 then
      return false, "completed"
    end

    self.length = task.size
    self.blocks = {}
    self.stop = false
    self.task = task

    if not self.peerurls then
      while true do
        local links = listfilelinks(task.path, session_value)
        if not links then
          print("task no links, wait for 10s.")
          fan.sleep(10)
        elseif not is_invalidate_links(links) then
          self.peerurls = links
          break
        else
          return false, "invalid resource."
        end
      end
    end

    self.path = getfilepath(task.path)

    local blocks = context.block("list", "where taskid=?", task.id)

    if #(blocks) > 0 then
      for i,v in ipairs(blocks) do
        self.blocks[v.id] = v
        start_task(self, v)
      end
    else
      start_task(self)
    end

    return true
  else
    return false, "running"
  end
end

function task_mt:save()
  commander:pathflush(self.path)

  for k,v in pairs(self.blocks) do
    v:update()
  end
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

  for _,v in pairs(self.blocks) do
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

local function verify_task_md5(r)
  if r.completed == 1 then
    if r.verified == 0 then
      print(r.path, "verifying md5 ...")
      local current_md5 = commander:getfilemd5(getfilepath(r.path))
      if current_md5 then
        if current_md5 == r.md5 or current_md5 == r.lastfailedmd5 then
          print(r.path, "md5 verified.", current_md5 == r.md5, current_md5 == r.lastfailedmd5)
          r.verified = 1
          r:update()
        else
          print(r.path, "md5 verify failed, marked as not complete.")
          os.remove(getfilepath(r.path))
          r.completed = 0
          r.lastfailedmd5 = current_md5
          r:update()
        end
      else
        print(r.path, "missing, marked as not complete.")
        r.completed = 0
        r:update()
      end
    end
  end
end

function task_mt:lifecycle()
  if self.task.completed == 1 or self.stop then
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

  local taskcount = 0

  for k,v in pairs(self.blocks) do
    if v.complete then
      if not v.endoffset or v.offset < v.endoffset then
        table.insert(restartneed, v)
        taskcount = taskcount + 1
      else
        v:delete()
      end
      table.insert(completed, k)
    else
      taskcount = taskcount + 1
    end
  end

  for _,v in ipairs(completed) do
    self.blocks[v] = nil
  end

  for _,v in ipairs(restartneed) do
    self.blocks[v.id] = v
    start_task(self, v)
  end

  while self.partable and taskcount < MAX_PEER_COUNT do
    local maxtask = nil
    local maxleft = 0

    for k,v in pairs(self.blocks) do
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

      local block = context.block("new", {
          taskid = self.taskid,
          beginoffset = center,
          offset = center,
          endoffset = maxtask.endoffset
        })

      -- print("new block", block.offset, block.beginoffset, block.endoffset)
      self.blocks[block.id] = block

      start_task(self, block)

      maxtask.endoffset = center
      taskcount = taskcount + 1
    else
      break
    end
  end

  if self.length and taskcount == 0 and self.task.completed == 0 then
    self.stop = true

    self.task.completed = 1
    self.task:update()
    print("finished", self.task.path)

    commander:pathclose(self.path)
    coroutine.wrap(verify_task_md5)(self.task)
  end
end

local function add(taskid, peerurls)
  print("add", taskid)
  local task = {
    taskid = taskid,
    peerurls = peerurls,
    current_downloaded = 0,
    speed = 0,
    last_mark_time = gettime(),
    last_mark_value = 0,
    stop = true,
    completed = false,
    blocks = {},
  }

  setmetatable(task, task_mt)
  table.insert(tasks, task)

  return task
end

local function list(running)
  return tasks
end

local download = {
  add = add,
  list = list,
  pause = pause,
  resume = resume,
}
-----download end -----

local function syncdiff(cursor)
  local list,has_more,reset,cursor = listdiff(cursor)
  if list then
    if reset then
      context:update("update task set exist=0")
    end

    for i,v in ipairs(list) do
      local task = context.task("one", "where path=?", v.path)
      if v.isdelete ~= 0 then
        if task then
          task.exist = 0
          task:update()

          if task.isdir == 1 then
            context:update("update task set exist=0 where parentpath=?", task.path)
          end
        end
      else
        if task then
          if task.md5 ~= v.md5 then
            task.verified = 0
            task.completed = 0
          end

          task.ctime = v.ctime
          task.mtime = v.mtime
          task.md5 = v.md5
          task.size = v.size
          task.exist = 1
          task:update()
        else
          local parentpath,name = string.match(v.path, "(.*)/([^/]+)")
          task = context.task("new", {
              path = v.path,
              parentpath = parentpath,
              name = name,
              size = v.size,
              md5 = v.md5,
              ctime = v.ctime,
              mtime = v.mtime,
              isdir = v.isdir
            })
        end
      end

      fan.sleep(0.001)
    end
  end

  return has_more, cursor
end

local function addtask(path, session)
  local list = listfiles(path, session)
  local locallist = context.task("list", "where parentpath=?", path)
  local exist_map = {}
  if list then
    for i,v in ipairs(list) do
      local task = context.task("one", "where path=?", v.path)
      local needdeepin = (v.isdir == 1)
      if not task then
        local parentpath,name = string.match(v.path, "(.*)/([^/]+)")
        task = context.task("new", {
            path = v.path,
            parentpath = parentpath,
            name = name,
            size = v.size,
            md5 = v.md5,
            ctime = v.ctime,
            mtime = v.mtime,
            isdir = v.isdir
          })
        print("new task:", task.id)
      else
        if v.mtime ~= task.mtime then
          task.mtime = v.mtime
          task.ctime = v.ctime
          task.isdir = v.isdir
          task:update()
        else
          needdeepin = false
        end
      end

      exist_map[task.id] = true

      if needdeepin then
        addtask(v.path, session)
      end
    end

    for i,v in ipairs(locallist) do
      if not exist_map[v.id] then
        v.exist = 0
        v:update()
      end
    end
  end
end

local sep = string.rep("-", 20)

local function infolist()
  while true do
    -- print("\x1Bc")
    local tasks = download.list()
    print("total tasks:", #(tasks))
    -- for k,v in pairs(tasks) do
    -- print("before",k,v)
    -- end

    local count = 0

    local speed = 0

    local completedlist = {}

    for _,v in ipairs(tasks) do
      -- print("lifecycle...", v.path)
      v:lifecycle()
      -- print("lifecycled", v.path)
      v:save()
      if v.task.completed == 0 then
        local info = v:info()
        print(string.format("%1.02f%% complete (%02d peers) (speed %1.02fKB/s) time left: %s %s", info.progress, info.peercount, info.speed / 1024, info.estimate, v.path))
        count = count + 1
        speed = speed + info.speed
      else
        table.insert(completedlist, v)
      end
    end

    for i,v in ipairs(completedlist) do
      for j,t in ipairs(tasks) do
        if v == t then
          table.remove(tasks, j)
          break
        end
      end
    end

    -- for k,v in pairs(tasks) do
    -- print("after",k,v)
    -- end

    if count < MAX_DOWNLOAD_COUNT then
      if download_queue_co then
        fan.sleep(0.001)
        print(coroutine.resume(download_queue_co))
      end
    end

    print(string.format("speed total: %1.02fKB", speed/1024))

    if count == 0 and exist_on_complete then
      print("all sync completed.")
      os.exit(0)
    end

    -- print("collectgarbage start")
    -- collectgarbage()
    -- print("collectgarbage done.")
    print("sleep 2")
    fan.sleep(2)
    print("wake")
  end
end

local function main()
  http.cookiejar("/dev/null")

  commander.wait_all_slaves()

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
      print(string.format("visit: %s/bind?code=%s", remote_url, map.code))
    else
      for k,v in pairs(ret) do
        print(k,v)
      end
    end

    os.exit(0)
  end

  session_value = session.value

  -- addtask(remotePath, session_value)
  local cursor_setting = context.setting("one", "where key=?", "cursor")
  if not cursor_setting then
    cursor_setting = context.setting("new", {
        key = "cursor",
        value = "null",
      })
  end

  local cursor = cursor_setting.value
  local has_more = true
  while has_more do
    has_more, cursor = syncdiff(cursor)
    cursor_setting.value = cursor
    cursor_setting:update()
  end

  info_co = coroutine.create(infolist)
  print("info_co", coroutine.resume(info_co))

  local total = 0
  context.task(function(r)
      if #(download.list()) >= MAX_DOWNLOAD_COUNT then
        download_queue_co = coroutine.running()
        coroutine.yield()
        download_queue_co = nil
      end

      verify_task_md5(r)

      if r.completed == 1 then
        return
      end

      local links
      while true do
        links = listfilelinks(r.path, session_value)
        if not links then
          print("can't get links, wait for 10s...")
          fan.sleep(10)
        elseif is_invalidate_links(links) then
          r.status = STATUS_INVALID
          r:update()
          return
        else
          break
        end
      end

      local task = download.add(r.id, links)
      assert(task:start())
      total = total + r.size
      end, "where exist=1 and verified=0 and status>=0 and isdir=0")

    exist_on_complete = true
  end

  main_co = coroutine.create(main)
  print("main_co", coroutine.resume(main_co))

  fan.loop()
