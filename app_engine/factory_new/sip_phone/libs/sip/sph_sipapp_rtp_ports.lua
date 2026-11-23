-- App-local allocator: avoid immediately reusing a previous UDP media endpoint.
-- Keep the cursor across SIP re-registration; never change a live dialog's port.
local M = {}
local cursors = {}
function M.allocate(base, dialogs)
    base = math.floor(tonumber(base) or 40000)
    assert(base>=1024 and base<=65534,"invalid RTP port base")
    base=base-base%2
    local port=cursors[base] or base
    for _=1,32256 do
        local candidate=port
        port=port+2
        if port>65534 then port=1024 end
        local used=false
        for _,dialog in pairs(dialogs or {}) do
            if dialog.local_rtp_port==candidate then used=true;break end
        end
        if not used then
            cursors[base]=port
            return candidate
        end
    end
    error("no available RTP port")
end
return M
