--[[
    testcase for mqttcore
    检验mqttcore是否存在内存泄漏的问题
]]
sys = require("sys")

local packCONNECT = mqttcore.packCONNECT
local packPUBLISH = mqttcore.packPUBLISH
local packSUBSCRIBE = mqttcore.packSUBSCRIBE
local packACK = mqttcore.packACK
local packZeroData = mqttcore.packZeroData

local PINGREQ = 12
local PUBACK = 4

function test_mqttcore_packCONNECT()
    local mc = {
        clientId = "123",
        keepAlive = 300,
        username = "luatos",
        password = "1234567890",
        cleanSession = 1
    }
    packCONNECT(mc.clientId, mc.keepAlive, mc.username, mc.password, mc.cleanSession, {topic="",payload="",qos=0,retain=0,flag=0})
end

function test_mqttcore_packPUBLISH()
    local topic = "/sys/abc/yyyzzz"
    local payload = json.encode({abc=123})
    payload = string.rep(payload, 1024)
    packPUBLISH(0, 0, 0, 0, topic, payload)
    packPUBLISH(0, 1, 0, 123, topic, payload)
end

function test_mqttcore_packSUBSCRIBE()
    packSUBSCRIBE(0, 1234, {mytopic=1})
end


function test_mqttcore_packZeroData()
    packZeroData(PINGREQ)
end

function test_mqttcore_packACK()
    local pkg = {packetId=123}
    packACK(PUBACK, 0, pkg.packetId)
end

sys.taskInit(function ()
    sys.wait(100)
    local testCount = 100 * 10000
    for i = 1, testCount, 1 do
        test_mqttcore_packCONNECT(i)
        test_mqttcore_packPUBLISH()
        test_mqttcore_packSUBSCRIBE()
        test_mqttcore_packACK()
        test_mqttcore_packZeroData()
    end
    log.info("sys", rtos.meminfo("sys"))
    log.info("lua", rtos.meminfo("lua"))
    os.exit(0)
end)

sys.run()
