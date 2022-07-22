network.setDNS(nil,1,"223.5.5.5")
network.setDNS(nil,2,"114.114.114.114")
require "dtu_demo"
dtuDemo(2, "112.125.89.8", 37553)
require "ntp_demo"
ntpDemo()
--require "ota_demo"
--otaDemo()
--require "server_demo"
--SerDemo(12000)