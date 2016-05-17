
local fan = require "fan"
local http = require "fan.http"
local download = require "download"

local url = "http://mirrors.opencas.cn/ubuntu-releases/16.04/ubuntu-16.04-desktop-amd64.iso"
-- local url = "http://download.taobaocdn.com/dingtalk-desktop/Release/install/DingTalk_v1.8.1.dmg"
local url = "http://mirrors.opencas.cn/ubuntu-releases/16.04/ubuntu-16.04-server-amd64.iso"

local function main()
    local urls = {
        "https://pcscdns.baidu.com/file/d69e509f04c5c6fb59f9b9bd53f096dd?bkt=p-bef9c797b0145784a2e2cf27a74f7f82&xcode=397c3a5f2feb3b0fa033db840cc4076480cc5831f1a201d294b92e463168dc1b&fid=1009988338-1506190-16130711091534&time=1463160565&sign=FDTAXGERLBH-DCb740ccc5511e5e8fedcff06b081203-uVIT6XVUlpq7%2Bq%2Fd5egdjf7cH7c%3D&to=nj2hb&fm=MH,Nan,N,T,t&sta_dx=155&sta_cs=0&sta_ft=avi&sta_ct=7&fm2=MH,Nanjing,N,T,t&newver=1&newfm=1&secfm=1&flow_ver=3&pkey=1400d69e509f04c5c6fb59f9b9bd53f096ddb6db7ae7000009b1ac70&sl=75104334&expires=8h&rt=pr&r=271826928&mlogid=3109278577010603248&vuk=-&vbdid=765599556&fin=%E6%91%84%E5%83%8F%E5%A4%B4%E8%B6%8A%E6%B8%85%E6%99%B0%E8%B6%8A%E6%9D%AF%E5%85%B7%28%E6%B2%A1%E5%85%B3%E6%91%84%E5%83%8F%E5%A4%B4%2C%E5%BF%98%E6%88%91%E5%91%90%E5%96%8A%29.avi&bflag=k,G,ik&slt=pm&uta=0&rtype=1&iv=0&isw=0&dp-logid=3109278577010603248&dp-callid=0.1.1&hps=1",
        "http://nj.poms.baidupcs.com/file/d69e509f04c5c6fb59f9b9bd53f096dd?bkt=p-bef9c797b0145784a2e2cf27a74f7f82&fid=1009988338-1506190-16130711091534&time=1463160565&sign=FDTAXGERLBH-DCb740ccc5511e5e8fedcff06b081203-mgHBIO1tjuLySHYfi4G9l3JV1Eg%3D&to=nb&fm=MH,Nan,N,T,t&sta_dx=155&sta_cs=0&sta_ft=avi&sta_ct=7&fm2=MH,Nanjing,N,T,t&newver=1&newfm=1&secfm=1&flow_ver=3&pkey=1400d69e509f04c5c6fb59f9b9bd53f096ddb6db7ae7000009b1ac70&sl=75104334&expires=8h&rt=pr&r=395278884&mlogid=3109278577010603248&vuk=-&vbdid=765599556&fin=%E6%91%84%E5%83%8F%E5%A4%B4%E8%B6%8A%E6%B8%85%E6%99%B0%E8%B6%8A%E6%9D%AF%E5%85%B7%28%E6%B2%A1%E5%85%B3%E6%91%84%E5%83%8F%E5%A4%B4%2C%E5%BF%98%E6%88%91%E5%91%90%E5%96%8A%29.avi&bflag=k,G,iG&slt=pm&uta=0&rtype=1&iv=0&isw=0&dp-logid=3109278577010603248&dp-callid=0.1.1",
        "http://nj01ct01.baidupcs.com/file/d69e509f04c5c6fb59f9b9bd53f096dd?bkt=p-bef9c797b0145784a2e2cf27a74f7f82&fid=1009988338-1506190-16130711091534&time=1463160565&sign=FDTAXGERLBH-DCb740ccc5511e5e8fedcff06b081203-hihGBjNo6CBHCReGGl6YjQfEBcM%3D&to=njhb&fm=MH,Nan,N,T,t&sta_dx=155&sta_cs=0&sta_ft=avi&sta_ct=7&fm2=MH,Nanjing,N,T,t&newver=1&newfm=1&secfm=1&flow_ver=3&pkey=1400d69e509f04c5c6fb59f9b9bd53f096ddb6db7ae7000009b1ac70&sl=75104334&expires=8h&rt=pr&r=245296451&mlogid=3109278577010603248&vuk=-&vbdid=765599556&fin=%E6%91%84%E5%83%8F%E5%A4%B4%E8%B6%8A%E6%B8%85%E6%99%B0%E8%B6%8A%E6%9D%AF%E5%85%B7%28%E6%B2%A1%E5%85%B3%E6%91%84%E5%83%8F%E5%A4%B4%2C%E5%BF%98%E6%88%91%E5%91%90%E5%96%8A%29.avi&bflag=k,G,ii&slt=pm&uta=0&rtype=1&iv=0&isw=0&dp-logid=3109278577010603248&dp-callid=0.1.1",
    }
    local task = download.add(urls[1], "a.avi", urls)
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