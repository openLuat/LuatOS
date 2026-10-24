-- Deterministic simulated connectivity cards. No radios, network APIs or IO.
-- enabled is the requested switch position; connected is true only after the
-- simulated transition completes. Every card is independent of the others.
local Network = {}
Network.__index = Network

local definitions = {
    {key="WIFI", title="WIFI", address="192.168.10.88", detail="Factory_Demo / -48 dBm"},
    {key="CELLULAR", title="4G", address="10.60.8.24", detail="演示运营商 / LTE / -72 dBm"},
    {key="ETHERNET", title="以太网", address="192.168.1.86", detail="LAN1 / 100 Mbps"},
    {key="BLUETOOTH", title="蓝牙", address="BT:86:01:00:00:01", detail="FactoryTwin_Demo / 已配对"}
}
local aliases = {WIFI="WIFI",["WI-FI"]="WIFI",CELLULAR="CELLULAR",CELL="CELLULAR",
    ["4G"]="CELLULAR",ETHERNET="ETHERNET",ETH="ETHERNET",LAN="ETHERNET",
    BLUETOOTH="BLUETOOTH",BT="BLUETOOTH"}
local function finite(value)
    return type(value)=="number" and value==value and value~=math.huge and value~=-math.huge
end
local function clone(value)
    if type(value)~="table" then return value end
    local result={}
    for key,item in pairs(value) do result[key]=clone(item) end
    return result
end

function Network.new(config)
    config=config or {}
    local transition=config.transition_ms
    if not finite(transition) or transition<0 then transition=400 end
    local self=setmetatable({elapsed_ms=0,transition_ms=transition,cards={},by_key={}},Network)
    for i,definition in ipairs(definitions) do
        local card=clone(definition)
        card.enabled,card.state,card.remaining_ms=false,"OFF",0
        self.cards[i],self.by_key[card.key]=card,card
    end
    return self
end

function Network:request(kind,enabled)
    if type(kind)~="string" then return false,"invalid_kind" end
    local key=aliases[string.upper(kind)]
    local card=key and self.by_key[key]
    if not card then return false,"invalid_kind" end
    if type(enabled)~="boolean" then return false,"invalid_enabled" end
    if card.enabled==enabled then return false,"unchanged" end
    card.enabled=enabled
    card.remaining_ms=self.transition_ms
    if self.transition_ms==0 then
        card.state=enabled and "CONNECTED" or "OFF"
    else
        card.state=enabled and "CONNECTING" or "DISCONNECTING"
    end
    return true
end

function Network:step(dt_ms)
    if not finite(dt_ms) or dt_ms<0 then return false,"invalid_dt" end
    self.elapsed_ms=self.elapsed_ms+dt_ms
    for _,card in ipairs(self.cards) do
        if card.state=="CONNECTING" or card.state=="DISCONNECTING" then
            card.remaining_ms=math.max(0,card.remaining_ms-dt_ms)
            if card.remaining_ms==0 then card.state=card.enabled and "CONNECTED" or "OFF" end
        end
    end
    return true
end

function Network:snapshot()
    local result={elapsed_ms=self.elapsed_ms,simulated=true,cards={},by_key={}}
    for i,card in ipairs(self.cards) do
        local item={key=card.key,title=card.title,enabled=card.enabled,state=card.state,
            connected=card.state=="CONNECTED",simulated=true,remaining_ms=card.remaining_ms,
            address=card.state=="CONNECTED" and card.address or "--"}
        if card.state=="CONNECTED" then item.detail="模拟已连接 / "..card.detail
        elseif card.state=="CONNECTING" then item.detail="模拟连接中"
        elseif card.state=="DISCONNECTING" then item.detail="模拟断开中"
        else item.detail="模拟已关闭" end
        result.cards[i],result.by_key[item.key]=item,clone(item)
    end
    return result
end

return Network
