-- 如果运营商自带的DNS不好用，可以用下面的公用DNS
-- network.setDNS(nil,1,"223.5.5.5")	
-- network.setDNS(nil,2,"114.114.114.114")
require "dtu_demo"
dtuDemo(1, "112.125.89.8", 37711)
require "ntp_demo"
ntpDemo()
require "http_demo"
require "mqtt_demo"
