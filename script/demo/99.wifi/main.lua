wlan.setMode("wlan0", wlan.STATION)
wlan.join("uiot", "ABC")
while wlan.connected() == false do
    timer.mdelay(1000)
    print("wait for connected")
end

print("connected")

while wlan.ready() == 0 do
    timer.mdelay(1000)
    print("wait for ready")
end

print("wifi is ready!!!")

while 1 do
    print("connecting ...")
    socket.tsend("111.230.171.211", 19001, "{hi:123}")
    print("connect end")
    timer.mdelay(10*1000)
end
