--[[
服务器统一管理

为了规范多个服务器, 屏蔽单一服务器与多个服务器差异, 改到这里来
]]

local srvs = {}

local ns = {}

function srvs.dataSend(data)
    for i = 1, #ns do
        local srv = ns[i]
        if srv.dataSend then
            local res, info = pcall(srv.dataSend, data)
            if not res then
                log.info("dataSend error info", info)
            end
        end
    end
end

function srvs.add(task)
    table.insert(ns, task)
end

function srvs.isConnected()
    for i = 1, #ns do
        local srv = ns[i]
        if srv.isConnected then
            return srv.isConnected()
        end
    end
end

return srvs
