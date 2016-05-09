
local fan = require "fan"
local http = require "fan.http"
local download = require "download"

local url = "http://mirrors.opencas.cn/ubuntu-releases/16.04/ubuntu-16.04-desktop-amd64.iso"
-- local url = "http://download.taobaocdn.com/dingtalk-desktop/Release/install/DingTalk_v1.8.1.dmg"
local url = "http://mirrors.opencas.cn/ubuntu-releases/16.04/ubuntu-16.04-server-amd64.iso"

local function main()
    local task = download.add("http://ftp.sjtu.edu.cn/ubuntu-cd/14.04.4/ubuntu-14.04.4-desktop-amd64.iso", "ubuntu-14.04.4-desktop-amd64.iso")
    task:start()

    local task = download.add("http://mirrors.opencas.cn/ubuntu-releases/16.04/ubuntu-16.04-server-amd64.iso", "ubuntu-16.04-server-amd64.iso")
    task:start()

    while true do
        print(string.rep("-", 20))
        local tasks = download.list()

        local count = 0

        for _,task in ipairs(tasks) do
            task:lifecycle()
            local info = task:info()
            print(string.format("%1.02f%% complete (%02d peers) (speed %1.02fKB/s) time left: %s %s", info.progress, info.peercount, info.speed / 1024, info.estimate, task.path))
            task:save()
            if not task.completed then
                count = count + 1
            end
        end

        if count == 0 then
            print("all download completed.")
            os.exit()
        end

        fan.sleep(2)
    end
end

fan.loop(main)