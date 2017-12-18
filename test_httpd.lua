local fan = require "fan"
local httpd = require "fan.httpd"

fan.loop(function()
    serv = httpd.bind{
        port = 8081,
        onService = function(req, resp)
            if req.path == "/smoketest" then
                resp:addheader("Server", "nginx/1.9.15")
                resp:addheader("Date", "Wed, 14 Jun 2017 04:44:33 GMT")
                resp:addheader("Content-Type", "text/html")
                resp:addheader("Connection", "keep-alive")
                return resp:reply(404, "Not Found", [[<html>
<head><title>404 Not Found</title></head>
<body bgcolor="white">
<center><h1>404 Not Found</h1></center>
<hr><center>nginx/1.9.15</center>
</body>
</html>]])
            end
            local t = {}
            resp:addheader("test", "head")
            resp:addheader("Content-Type", "text/plain; charset=utf-8")

            resp:reply_start(200, "OK")

            resp:reply_chunk(string.format("ip %s:%d\r\n", req.remoteip, req.remoteport))

            resp:reply_chunk(string.format("path %s\r\n", req.path))

            for k,v in pairs(req.params) do
                resp:reply_chunk(string.format("%s = %s\r\n", k, v))
            end
            resp:reply_chunk("\r\n")
            for k,v in pairs(req.headers) do
                resp:reply_chunk(string.format("%s: %s\r\n", k, v))
            end

            resp:reply_chunk(req.body)

            resp:reply_end()
        end
    }
end)