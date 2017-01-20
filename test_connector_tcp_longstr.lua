local fan = require "fan"
local stream = require "fan.stream"
local connector = require "fan.connector"

local data = string.rep([[coroutine.create]], 10000)

local co = coroutine.create(function()
    serv = connector.bind("tcp://127.0.0.1:10000")
    serv.onaccept = function(apt)
      print("onaccept")
      local last_expect = 1

      while true do
        local input = apt:receive(last_expect)
        if not input then
          break
        end
        -- print("serv read", input:available())

        local str,expect = input:GetString()
        if str then
          last_expect = 1
          
          assert(str == data)

          local d = stream.new()
          d:AddString(str)
          apt:send(d:package())
        else
          last_expect = expect
        end
      end
    end
  end)
coroutine.resume(co)

fan.loop(function()
    cli = connector.connect("tcp://127.0.0.1:10000")
    local d = stream.new()
    d:AddString(data)
    cli:send(d:package())

    local last_expect = 1

    while true do
      local input = cli:receive(last_expect)
      if not input then
        break
      end
      -- print("cli read", input:available())

      local str,expect = input:GetString()
      if str then
        last_expect = 1

        assert(str == data)

        local d = stream.new()
        d:AddString(str)
        cli:send(d:package())
      else
        last_expect = expect
      end
    end
  end)
