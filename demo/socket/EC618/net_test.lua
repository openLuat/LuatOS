-- 如果运营商自带的DNS不好用，可以用下面的公用DNS
-- socket.setDNS(nil,1,"223.5.5.5")	
-- socket.setDNS(nil,2,"114.114.114.114")
-- require "socket_demo"
-- dtuDemo(1, "112.125.89.8", 35009)
-- require "ntp_demo"
-- ntpDemo()
require "async_socket_demo"
socketDemo()
-- UDPDemo()
-- SSLDemo()