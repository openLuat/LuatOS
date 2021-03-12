--[[
异步MQTT客户端
1. 自动重连
2. 异步收发信息

暂不支持的特性:
1. qos 2的消息不被支持,以后也不会添加
2. 不支持取消订阅(也许会添加,也许不会)

用法请参考demo

]]

-- MQTT 指令id
local CONNECT, CONNACK, PUBLISH, PUBACK, PUBREC, PUBREL, PUBCOMP, SUBSCRIBE, SUBACK, UNSUBSCRIBE, UNSUBACK, PINGREQ, PINGRESP, DISCONNECT = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14
local CLIENT_COMMAND_TIMEOUT = 60000

local packCONNECT = mqttcore.packCONNECT
local packPUBLISH = mqttcore.packPUBLISH
local packSUBSCRIBE = mqttcore.packSUBSCRIBE
local packACK = mqttcore.packACK
local packZeroData = mqttcore.packZeroData
local mclog = log.debug
local unpack = mqttcore.unpack

local mqtt2 = {}

local mqttc = {}
mqttc.__index = mqttc

function mqtt2.new(clientId, keepAlive, username, password, cleanSession, host, port, topics, cb, ckey)
    local c = {
        clientId = clientId,
        keepAlive = keepAlive or 300,
        username = username or "",
        password = password or "",
        cleanSession = cleanSession == nil and 1 or 0,
        host = host,
        port = port,
        lping = 0,
        stat = 0, -- 状态 0, 未连接, 1 已连接成功
        nextid = 0, -- pkg的ID
        running = false,
        inpkgs = {},
        outpkgs = {},
        buff = "",
        topics = topics or {},
        cb = cb,
        ckey = ckey or ""
    }
    if c.ckey == "" then c.ckey = "mqtt_" .. tostring(c) end
    --mclog("mqtt", "MQTT Client Key", c.ckey)
    setmetatable(c, mqttc)
    return c
end

-- 内部方法, 用于获取下一个pkg的id
function mqttc:genId()
    self.nextid = self.nextid == 65535 and 1 or (self.nextid + 1)
    --mclog("mqtt", "next packet id", self.nextid)
    return self.nextid
end

-- 内部方法,用于处理待处理的数据包
function mqttc:handle(netc)
    local mc = self
    -- 先处理服务器下发的数据包
    if #mc.inpkgs > 0 then
        --mclog("mqtt", "inpkgs count", #mc.inpkgs)
        while 1 do
            local pkg = table.remove( mc.inpkgs, 1 )
            if pkg == nil then
                break
            end
            -- 处理服务器下发的包
            --mclog("mqtt", "handle pkg", json.encode(pkg))
            if pkg.id == CONNACK then
                mc.stat = 1
                mc.lping = os.time()
                --mclog("mqtt", "GOT CONNACK")
                for k, v in pairs(mc.topics) do
                    --mclog("mqtt", "sub topics", json.encode(mc.topics))
                    netc:send(packSUBSCRIBE(0, mc:genId(), mc.topics))
                    break
                end
            elseif pkg.id == PUBACK then
                --mclog("mqtt", "GOT PUBACK")
                sys.publish(mc.ckey .. "PUBACK")
            elseif pkg.id == SUBACK then
                --mclog("mqtt", "GOT SUBACK")
                sys.publish(mc.ckey .. "SUBACK")
            elseif pkg.id == PINGRESP then
                mc.lping = os.time()
                --mclog("mqtt", "GOT PINGRESP", mc.lping)
            elseif pkg.id == UNSUBACK then
                --mclog("mqtt", "GOT UNSUBACK")
            elseif pkg.id == DISCONNECT then
                --mclog("mqtt", "GOT DISCONNECT")
            elseif pkg.id == PUBLISH then
                --mclog("mqtt", "GOT PUBLISH", pkg.topic, pkg.qos)
                if pkg.qos > 0 then
                    -- 发送PUBACK
                    --mclog("mqtt", "send back PUBACK")
                    table.insert( mc.outpkgs, packACK(PUBACK, 0, pkg.packetId))
                end
                if mc.cb then
                    --mclog("mqtt", "Callback for PUBLISH", mc.cb)
                    mc.cb(pkg)
                end
            end
        end
    end
    -- 处理需要上报的数据包
    if #mc.outpkgs > 0 then
        --mclog("mqtt", "outpkgs count", #mc.outpkgs)
        while 1 do
            local buff = table.remove( mc.outpkgs, 1)
            if buff == nil then
                break
            end
            --mclog("mqtt", "netc send", buff:toHex())
            netc:send(buff)
        end
    end
    -- 是否需要发心跳
    if mc.lping > 0 and os.time() - mc.lping > mc.keepAlive * 0.75 then
        --mclog("mqtt", "time for ping", mc.lping)
        mc.lping = os.time()
        netc:send(packZeroData(PINGREQ)) -- 发送心跳包
    end
end

-- 启动mqtt task, 要么在task里面执行, 要么新建一个task执行本方法
function mqttc:run()
    local mc = self
    mc.running = true
    while mc.running do
        if socket.isReady() then
            -- 先复位全部临时对象
            mc.buff = ""
            mc.inpkgs = {}
            mc.outpkgs = {}
            -- 建立socket对象
            --mclog("mqtt", "try connect")
            local netc = socket.tcp()
            netc:host(mc.host)
            netc:port(mc.port)
            netc:on("connect", function(id, re)
                --mclog("mqtt", "connect", id , re)
                if re then
                    -- 发送CONN包
                    table.insert(mc.outpkgs, packCONNECT(mc.clientId, mc.keepAlive, mc.username, mc.password, mc.cleanSession, {topic="",payload="",qos=0,retain=0,flag=0}))
                    sys.publish(mc.ckey)
                end
            end)
            netc:on("recv", function(id, data)
                --mclog("mqtt", "recv", id , data:sub(1, 10):toHex())
                mc.buff = mc.buff .. data
                while 1 do
                    local packet, nextpos = unpack(mc.buff)
                    if not packet then
                        if #mc.buff > 4096 then
                            log.warn("mqtt", "packet is too big!!!")
                            netc:close()
                        end
                        break
                    else
                        mc.buff = mc.buff:sub(nextpos)
                        --mclog("mqtt", "recv new pkg", json.encode(packet))
                        table.insert( mc.inpkgs, packet)
                        if #mc.buff < 2 then
                            break
                        end
                    end
                end
                if #mc.inpkgs > 0 then
                    sys.publish(mc.ckey)
                end
            end)
            if netc:start() == 0 then
                --mclog("mqtt", "start success")
                local endTopic = "NETC_END_" .. netc:id()
                while (netc:closed()) == 0 do
                    mc:handle(netc)
                    sys.waitUntil({endTopic, mc.ckey}, 30000)
                    if not mc.running then netc:close() end
                    --mclog("mqtt", "handle/timeout/ping", (netc:closed()))
                end
            end
            -- 清理socket上下文
            mclog("mqtt", "clean up")
            netc:clean()
            netc:close()
            -- 将所有状态复位
            mc.stat = 0

            mclog("mqtt", "wait 5s for next loop")
            sys.wait(5*1000) -- TODO 使用级数递增进行延时
        else
            sys.wait(1000)
        end
    end
    -- 线程退出, 只可能是用户主动shutdown
    mclog("mqtt", self.ckey, "exit")
end

-- 订阅topic, table形式
function mqttc:sub(topics)
    table.insert(self.outpkgs, packSUBSCRIBE(0, self:genId(), topics))
    sys.publish(self.ckey)
    return sys.waitUntil(self.ckey .. "SUBACK", 30000)
end

-- 上报数据
function mqttc:pub(topic, qos, payload)
    -- local function packPUBLISH(dup, qos, retain, packetId, topic, payload)
    table.insert(self.outpkgs, packPUBLISH(0, qos, 0, qos > 0 and self:genId() or 0, topic, payload))
    sys.publish(self.ckey)
    if qos > 0 then
        return sys.waitUntil(self.ckey .. "PUBACK", 30000)
    end
end

function mqttc:shutdown()
    self.running = false
    sys.publish(self.ckey)
end

return mqtt2
