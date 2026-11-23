-- Bounded migration reader: never materialize a legacy history file in memory.
local M = {}
function M.read(file, key)
    local chunk, pos = file:read(1024), 1
    assert(type(chunk)=="string" and #chunk>0,"empty history file")
    -- Small files need no migration buffer; also accept legacy empty Lua tables
    -- encoded as {} rather than [] by the JSON library.
    if #chunk<1024 then
        local data=json.decode(chunk)
        assert(type(data)=="table","invalid history JSON")
        local items=key=="calls" and data or data.items
        assert(type(items)=="table" and (next(items)==nil or items[1]~=nil),"invalid history array")
        local count=#items
        for _,item in ipairs(items) do assert(type(item)=="table","invalid history item") end
        if key=="calls" then
            while #items>5 do table.remove(items) end
        else
            while #items>5 do table.remove(items,1) end
            local seq=tonumber(data.seq) or 0
            for _,m in ipairs(items) do seq=math.max(seq,tonumber(m.id) or 0) end
            data.seq=seq
        end
        return data,count
    end
    local function next_char()
        if pos > #chunk then chunk=file:read(1024);pos=1 end
        if not chunk or #chunk==0 then return nil end
        local c=chunk:sub(pos,pos);pos=pos+1;return c
    end
    local function nonspace()
        local c=next_char()
        while c and c:match("%s") do c=next_char() end
        return c
    end
    local prefix=""
    local c=nonspace()
    if key=="messages" then
        assert(c=="{", "invalid message history")
        prefix=c
        repeat
            c=next_char();assert(c,"missing items")
            prefix=prefix..c;assert(#prefix<=4096,"history header too large")
        until c=="["
        assert(prefix:match('"items"%s*:%s*%[$'), "invalid items array")
    else assert(c=="[","invalid call history") end
    local out,total={},0
    c=nonspace()
    while c~= "]" do
        assert(c=="{","invalid history item")
        local chars,depth,quoted,escaped={c},1,false,false
        while depth>0 do
            c=next_char();assert(c,"truncated history")
            chars[#chars+1]=c;assert(#chars<=16384,"history item too large")
            if quoted then
                if escaped then escaped=false
                elseif c=="\\" then escaped=true
                elseif c=='"' then quoted=false end
            elseif c=='"' then quoted=true
            elseif c=="{" then depth=depth+1
            elseif c=="}" then depth=depth-1 end
        end
        local item=json.decode(table.concat(chars));assert(type(item)=="table","invalid history JSON")
        total=total+1
        if key=="messages" or #out<5 then out[#out+1]=item end
        if #out>5 then table.remove(out,1) end
        c=nonspace()
        if c=="," then c=nonspace();assert(c~="]","trailing comma")
        else assert(c=="]","invalid history separator") end
    end
    local suffix=""
    c=next_char()
    while c do suffix=suffix..c;assert(#suffix<=4096,"history footer too large");c=next_char() end
    if key=="calls" then assert(not suffix:match("%S"),"trailing history data");return out,total end
    local meta=json.decode(prefix.."]"..suffix)
    assert(type(meta)=="table" and type(meta.items)=="table","invalid message metadata")
    meta.items=out
    local seq=tonumber(meta.seq) or 0
    for _,m in ipairs(out) do seq=math.max(seq,tonumber(m.id) or 0) end
    meta.seq=seq
    return meta,total
end
return M
