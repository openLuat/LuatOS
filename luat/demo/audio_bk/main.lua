PROJECT = "adcdemo"
VERSION = "1.0.0"
SSID = "goat"
WIFIPASS = "Linxumeng1234"
AccessKeyID = "LTAI5tNJonTcotn8XYFqD5eq"
AccessKeySecret = "MtvSCvWf1jnpZljeLILMkRRR7tZKTF"
sys = require("sys")
sysplus = require("sysplus")
libnet = require "libnet"
log.setLevel(1)
log.info("main", PROJECT, VERSION)

pendingData = nil
function ConnectWifi()
	-- 联网 对表
	wlan.init()
	wlan.connect(SSID, WIFIPASS)
	log.info("wlan", "wait for IP_READY")
	sys.waitUntil("IP_READY", 30000)
	if wlan.ready() then
		log.info("wlan", "ready !!")
	end
end
ping = zbuff.create(42)
pong = zbuff.create(42)
function audioCallback(audio_id, msg,data)
    if msg == audio.RECORD_DATA then
		if(data==1)then
			pendingData = pong:toStr()
		else
			pendingData = ping:toStr()
		end
	end
end
-- 联网

audio.setBus(0, audio.BUS_DAC)
audio.vol(0,70);
audio.micVol(0,100);
audio.start(0, audio.PCM,1, 8000, 16) -- 通道0，PCM格式，单声道，采样率16000Hz，16位深度
audio.on(0, audioCallback)
audio.record(0, audio.PCM, 0, 0, nil,1,ping,pong,audio.RECORD_STEREO)

function main()
	ConnectWifi()
	local netc = socket.create(nil, "main")
	socket.config(netc, 8899, true, false)
	local result = libnet.connect( "main", 15000, netc, "192.168.32.200", 8899)
	
	if result then
		log.info("socket", "服务器连上了")
	else
		log.info("socket", "服务器没连上了!!!")
	end
	libnet.tx( "main", 0, netc, "helloworld")
	local rolling=0
	local buff = zbuff.create(1024)
	while true do
		sys.wait(10)
		local ok, param = socket.rx(netc, buff)
		if ok and buff ~= nil and buff:used() > 0 then
			while true do
				local resu = audio.write(0,buff) 
				if resu then 
					break
				end
			end
			libnet.tx( "main", 0, netc, "OK")
		end
		if buff ~= nil then
			buff:del()
		end
		if pendingData then
			local max_size = 1000 -- 每段的最大字节数 udp MTU(一包最多)约1400
			local total_length = #pendingData
			local offset = 0
			while offset < total_length do
				local send_length = math.min(max_size, total_length - offset)
				local segment = pendingData:sub(offset + 1, offset + send_length)
				libnet.tx("main", 0, netc, string.pack("<I", rolling) .. segment)
				rolling = rolling +1
				offset = offset + send_length
			end
			pendingData = nil
		end
	end
end

local function netCB(msg)
	--log.info("未处理消息", msg[1], msg[2], msg[3], msg[4])
end
local txqueue = {}
sysplus.taskInitEx(	main, "main", netCB, "main", txqueue, "main")
sys.run()