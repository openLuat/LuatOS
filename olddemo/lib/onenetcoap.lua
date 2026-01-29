--[[
@module onenetcoap
@summary 中移动OneNet平台COAP接入
@version 1.0
@date    2023.11.17
@author  wendal
@demo    onenet/coap
@tag LUAT_USE_NETWORK
@usage
-- 使用方法请查阅demo
]]


local onenet = {}
local TAG = "onenet.coap"

--[[
初始化onenet coap库
@onenet.setup(conf)
@table 配置项信息,必须有
@return boolean 成功返回true,否则返回nil
@usage
-- 配置信息是一个table,具体键值如下:
-- product_id 产品id,字符串,必须有
-- device_name 设备名称,字符串,必须有
-- device_key 设备密钥,字符串,必须有
-- host coap服务器地址,字符串,默认"183.230.102.122"
-- port coap服务器端口,整数,默认5683
-- auto_reply 自动回复thing获取,布尔值,默认关闭false
-- thing 物模型,类型是table,默认 {params={}}
-- debug 调试开关,默认关闭false
-- adapter 适配器编号,默认是最后一个注册的适配器
-- callback 收到合法coap数据时的用户回调
]]
function onenet.setup(conf)
    if not conf then
        return
    end
    if not conf.product_id then
        log.error(TAG, "配置信息缺product_id")
        return
    end
    if not conf.device_name then
        log.error(TAG, "配置信息缺device_name")
        return
    end
    if not conf.device_key then
        log.error(TAG, "配置信息缺device_key")
        return
    end
    onenet.product_id = conf.product_id
    onenet.device_name = conf.device_name
    -- log.info(">>", onenet.product_id, onenet.device_name, conf.device_key)
    _, _, onenet.login_token = iotauth.onenet(onenet.product_id, onenet.device_name, conf.device_key, "sha1")
    -- log.info("onenet.login_token", onenet.login_token)

    onenet.host = conf.host or "183.230.102.122"
    onenet.port = conf.port or 5683

    onenet.auto_reply = conf.auto_reply
    onenet.topic = conf.topic or "onenet_udp_inc"
    onenet.thing = conf.thing or {
        params = {}
    }
    onenet.debug = conf.debug
    onenet.thing_id = 1
    onenet.state = 0
    onenet.adapter = conf.adapter
    onenet.timeout = conf.timeout or 3000
    onenet.rx_buff = zbuff.create(1500)
    onenet.callback = conf.callback
    return true
end

function onenet.netc_cb(sc, event)
    -- log.info("udp", sc, string.format("%08X", event))
    local rxbuff = onenet.rx_buff
    if event == socket.EVENT then
        local ok, len, remote_ip, remote_port = socket.rx(sc, rxbuff)
        if ok then
            local data = rxbuff:query()
            rxbuff:del()
            log.info(TAG, "读到数据", data:toHex())
            ercoap.print(data)
            local resp = ercoap.parse(data)
            if resp and resp.code == 201 then
                log.info(TAG, "login success", resp.code, resp.payload:toHex())
                -- 这里非常重要, 获取其他请求所需要的token值
                onenet.post_token = resp.payload
                onenet.state = 2
                sys.publish(onenet.topic)
            end
            if resp then
                if onenet.callback then
                    onenet.callback(resp)
                else
                    sys.publish(onenet.topic, resp)
                end
            end
        else
            log.info(TAG, "服务器断开了连接")
            onenet.state = 0
            sys.publish(onenet.topic)
        end
    elseif event == socket.TX_OK then
        log.info(TAG, "上行完成")
    elseif event == socket.ON_LINE then
        log.info(TAG, "UDP已准备就绪,可以上行")
        -- 上行登陆包
        -- log.info("登陆参数", onenet.product_id, onenet.device_name, onenet.login_token)
        local data = ercoap.onenet("login", onenet.product_id, onenet.device_name, onenet.login_token)
        -- log.info("上行登陆包", data:toHex())
        socket.tx(sc, data)
    else
        log.info(TAG, "其他事件", event)
    end
end

function onenet.main_task()
    onenet.state = 1
    while onenet.state ~= 0 do
        local ok = onenet.main_loop()
        if not ok then
            sys.wait(500)
        end
    end
end

function onenet.main_loop()
    if onenet.netc == nil then
        onenet.netc = socket.create(onenet.adapter, onenet.netc_cb)
    end
    if onenet.netc == nil then
        log.info(TAG, "创建socket失败!!! 3秒后重试")
        return
    end
    local netc = onenet.netc
    if onenet.state ~= 2 then
        socket.config(netc, nil, true)
        if onenet.debug then
            socket.debug(netc, true)
        end
        socket.connect(netc, onenet.host, onenet.port)
        local result, resp = sys.waitUntil(onenet.topic, onenet.timeout)
        if not result then
            log.info(TAG, "等待底层连接成功超时了")
            return
        end
    end
    sys.waitUntil(onenet.topic, 3000)
    return
end

function onenet.start()
    if onenet.state ~= 0 then
        log.info("onenet", "coap", "已经在启动状态,不需要再启动")
        return
    end
    sys.taskInit(onenet.main_task)
    return true
end

function onenet.uplink(tp, payload)
    if not tp then
        return
    end
    if payload and payload["id"] == nil then
        payload["id"] = "1"
    end
    if type(payload) == "table" then
        payload = json.encode(payload, "7f")
    end
    -- log.info("uplink", onenet.product_id, onenet.device_name, onenet.post_token:toHex(), payload)
    local tmp = ercoap.onenet(tp, onenet.product_id, onenet.device_name, onenet.post_token, payload)
    -- log.info("uplink", tp, tmp:toHex())
    socket.tx(onenet.netc, tmp)
    return true
end

return onenet
