-- Official APIs: sys.publish, log, json.encode, optional http.request(...).wait().
-- Delivery states are explicit. A local event is NOT a server acknowledgement.
local M = {}
M.__index = M

function M.new(config)
    return setmetatable({config = config, queue = {}, sent = 0, failed = 0,
        local_count = 0, state = "LOCAL", last_error = nil}, M)
end

function M:accept(event)
    sys.publish("FACTORY_EVENT", event)
    if event.kind ~= "FAULT_REPORTED" then return end
    self.local_count = self.local_count + 1
    local body = json.encode({schema = "factory.alarm.v1", simulated = true,
        alarm = event, project = PROJECT, version = VERSION})
    log.warn("FACTORY_ALARM", body)
    sys.publish("FACTORY_ALARM", event)
    if not self.config.report_url or self.config.report_url == "" then
        self.state = "LOCAL"
        return
    end
    if #self.queue >= self.config.report_queue_limit then
        self.failed = self.failed + 1
        self.state, self.last_error = "FAILED", "queue full"
        log.error("FACTORY_REPORT", "queue full", event.id)
        return
    end
    self.queue[#self.queue + 1] = {body = body, id = event.id}
    self.state = "QUEUED"
    sys.publish("FACTORY_REPORT_PENDING")
end

function M:start()
    if not self.config.report_url or self.config.report_url == "" then return end
    -- Run only in an independent sys task; UI timers never wait for networking.
    sys.taskInit(function()
        while true do
            if #self.queue == 0 then sys.waitUntil("FACTORY_REPORT_PENDING", 1000) end
            if #self.queue > 0 then
                local item = table.remove(self.queue, 1)
                local delivered = false
                for attempt = 1, 3 do
                    self.state = "SENDING"
                    if http and http.request then
                        local ok, code = pcall(function()
                            return http.request("POST", self.config.report_url,
                                self.config.report_headers, item.body,
                                {timeout = self.config.report_timeout_ms}).wait()
                        end)
                        if ok and type(code) == "number" and code >= 200 and code < 300 then
                            delivered = true
                            break
                        end
                        self.last_error = tostring(code)
                    else
                        self.last_error = "http unavailable"
                    end
                    if attempt < 3 then sys.wait(attempt * 2000) end
                end
                if delivered then
                    self.sent, self.state = self.sent + 1, "SENT"
                    self.last_error = nil
                    sys.publish("FACTORY_REPORT_ACK", item.id)
                else
                    self.failed, self.state = self.failed + 1, "FAILED"
                    log.error("FACTORY_REPORT", item.id, self.last_error)
                    sys.publish("FACTORY_REPORT_FAILED", item.id, self.last_error)
                end
            end
        end
    end)
end

return M
