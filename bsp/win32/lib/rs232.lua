------------------------------------------------------------------
--
--  Author: Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  Copyright (C) 2015-2016 Alexey Melnichuk <alexeymelnichuck@gmail.com>
--
--  This file is part of lua-rs232 library.
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
-- 
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
-- 
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
------------------------------------------------------------------

local rs232 = require "rs232.core"

local function class(base)
  local t = base and setmetatable({}, base) or {}
  t.__index = t
  t.__class = t
  t.__base  = base

  function t.new(...)
    local o = setmetatable({}, t)
    if o.__init then
      if t == ... then -- we call as Class:new()
        return o:__init(select(2, ...))
      else             -- we call as Class.new()
        return o:__init(...)
      end
    end
    return o
  end

  return t
end

local function select_by_prefix(pfx, p)
  local names  = {}
  local values = {}
  p = p or ''

  for k, v in pairs(rs232) do
    if type(k) == 'string' and type(v) == 'number' then
      if k:sub(1, #pfx) == pfx then
        local name = p .. k:sub(#pfx+1)
        assert(not names[v])
        names[v]     = name
        values[name] = v
      end
    end
  end

  return values, names
end

local ERROR, ERROR_NAMES = select_by_prefix'RS232_ERR_'

local BAUD_NAMES, BAUD do
local tmp = select_by_prefix'RS232_BAUD_'
BAUD_NAMES, BAUD = {}, {}

for k, v in pairs(tmp) do
  BAUD_NAMES[ '_'    .. k ] = v
  BAUD_NAMES['BAUD_' .. k ] = v
  BAUD[v] =  'BAUD_' .. k
end

end

local DATA_NAMES, DATA do

local tmp = select_by_prefix'RS232_DATA_'
DATA_NAMES, DATA = {}, {}

for k, v in pairs(tmp) do
  DATA_NAMES[ '_' .. k    ] = v
  DATA_NAMES['DATA_' .. k ] = v
  DATA[v] =  'DATA_' .. k
end

end

local DTR_NAMES, DTR = select_by_prefix'RS232_DTR_'

local RTS_NAMES, RTS = select_by_prefix'RS232_RTS_'

local FLOW_NAMES, FLOW = select_by_prefix'RS232_FLOW_'

local PARITY_NAMES, PARITY = select_by_prefix'RS232_PARITY_'

local STOP_NAMES, STOP do

local tmp = select_by_prefix'RS232_STOP_'
STOP_NAMES, STOP = {}, {}

for k, v in pairs(tmp) do
  STOP_NAMES[ '_' .. k  ] = v
  STOP_NAMES['STOP_' .. k ] = v
  STOP[v] =  'STOP_' .. k
end

end

local RS232Error = class() do

function RS232Error:__init(no, ext)
  self._no   = no
  self._name = assert(ERROR_NAMES[no])
  self._ext  = ext
  return self
end

function RS232Error:cat()  return 'RS232'     end

function RS232Error:no()   return self._no    end

function RS232Error:name() return self._name end

function RS232Error:msg()  return rs232.error_tostring(self._no) end

function RS232Error:ext()  return self._ext   end

function RS232Error:__eq(rhs)
  return self._no == rhs._no
end

function RS232Error:__tostring()
  local err = string.format("[%s][%s] %s (%d)",
    self:cat(), self:name(), self:msg(), self:no()
  )
  if self:ext() then
    err = string.format("%s - %s", err, self:ext())
  end
  return err
end

end

local ERRORS = {
  [rs232.RS232_ERR_TIMEOUT] = RS232Error.new(rs232.RS232_ERR_TIMEOUT);
}

local function Error(e)
  return ERRORS[e] or RS232Error.new(e)
end

local function F(e, ...)
  if e ~= rs232.RS232_ERR_NOERROR then
    return nil, Error(e)
  end

  return true, ...
end

local Port = class() do

function Port:__init(name, opt)
  self._name = assert(name)
  self._opt = {}
  for k,v in pairs(opt or {})do
    self._opt[k] = v
  end

  return self
end

function Port:open()
  local ok, ret = F(rs232.open(self._name))
  if not ok then return nil, ret end
  self._p = ret

  ok, ret = self:set(self._opt)
  if not ok then
    self._p:close()
    return nil, err
  end

  return self, tostring(self._p)
end

function Port:close(...)
  if not self._p then return end

  self._p:close()
  self._p = nil
  return 
end

function Port:set(port_opt)
  local p = self._p

  local ok, err

  if port_opt.baud ~= nil then
    ok, err = self:set_baud_rate(port_opt.baud)
    if not ok then return nil, err end
  end

  if port_opt.baud_rate ~= nil then
    ok, err = self:set_baud_rate(port_opt.baud_rate)
    if not ok then return nil, err end
  end

  if port_opt.data_bits ~= nil then
    ok, err = self:set_data_bits(port_opt.data_bits)
    if not ok then return nil, err end
  end

  if port_opt.parity ~= nil then
    ok, err = self:set_parity(port_opt.parity)
    if not ok then return nil, err end
  end

  if port_opt.stop_bits ~= nil then
    ok, err = self:set_stop_bits(port_opt.stop_bits)
    if not ok then return nil, err end
  end

  if port_opt.flow_control ~= nil then
    ok, err = self:set_flow_control(port_opt.flow_control)
    if not ok then return nil, err end
  end

  if port_opt.rts ~= nil then
    ok, err = self:set_rts(port_opt.rts)
    if not ok then return nil, err end
  end

  if port_opt.dtr ~= nil then
    ok, err = self:set_dtr(port_opt.dtr)
    if not ok then return nil, err end
  end

  return self
end

function Port:read(...)
  local e, data, len = self._p:read(...)

  if e ~= rs232.RS232_ERR_NOERROR then
    if e == rs232.RS232_ERR_TIMEOUT then
      return data or ''
    end
    return data, Error(e)
  end

  return data
end

function Port:write(...)
  local ok, len = F(self._p:write(...))
  if not ok then return nil, len end
  return len
end

function Port:flush(...)
  local ok, err = F(self._p:flush(...))
  if not ok then return nil, err end
  return self
end

function Port:in_queue_clear(...)
  local ok, err = F(self._p:in_queue_clear(...))
  if not ok then return nil, err end
  return self
end

function Port:in_queue(...)
  local ok, len = F(self._p:in_queue(...))
  if not ok then return nil, len end
  return len
end

function Port:device(...)
  local ok, name = F(self._p:in_queue(...))
  if not ok then return nil, name end
  return name
end

function Port:fd(...)
  local ok, fd = F(self._p:fd(...))
  if not ok then return nil, fd end
  return fd
end

local function check_val(value, NAMES, VALUES)
  local v
  if type(value) == 'string' then
    v = assert( NAMES[value:upper()], 'Unsupported value:' .. tostring(value) )
  else
    v = value
    assert( VALUES[value], 'Unsupported value:' .. tostring(value) )
  end
  return v
end

function Port:set_baud_rate(value)
  local v = check_val(value, BAUD_NAMES, BAUD)

  local ok, err = F(self._p:set_baud_rate(v))
  if not ok then return nil, err end

  return self
end

function Port:baud_rate()
  local val = self._p:baud_rate()
  return val, BAUD[val]
end

function Port:set_data_bits(value)
  local v = check_val(value, DATA_NAMES, DATA)

  local ok, err = F(self._p:set_data_bits(v))
  if not ok then return nil, err end

  return self
end

function Port:data_bits()
  local val = self._p:data_bits()
  return val, DATA[val]
end

function Port:set_stop_bits(value)
  local v = check_val(value, STOP_NAMES, STOP)

  local ok, err = F(self._p:set_stop_bits(v))
  if not ok then return nil, err end

  return self
end

function Port:stop_bits()
  local val = self._p:stop_bits()
  return val, STOP[val]
end

function Port:set_parity(value)
  local v = check_val(value, PARITY_NAMES, PARITY)

  local ok, err = F(self._p:set_parity(v))
  if not ok then return nil, err end

  return self
end

function Port:parity()
  local val = self._p:parity()
  return val, PARITY[val]
end

function Port:set_flow_control(value)
  local v = check_val(value, FLOW_NAMES, FLOW)

  local ok, err = F(self._p:set_flow_control(v))
  if not ok then return nil, err end

  return self
end

function Port:flow_control()
  local val = self._p:flow_control()
  return val, FLOW[val]
end

function Port:set_dtr(value)
  local v = check_val(value, DTR_NAMES, DTR)

  local ok, err = F(self._p:set_dtr(v))
  if not ok then return nil, err end

  return self
end

function Port:dtr()
  local val = self._p:dtr()
  return val, DTR[val]
end

function Port:set_rts(value)
  local v = check_val(value, RTS_NAMES, RTS)

  local ok, err = F(self._p:set_rts(v))
  if not ok then return nil, err end

  return self
end

function Port:rts()
  local val = self._p:rts()
  return val, RTS[val]
end

function Port:__tostring()
  return "RS232 Port " .. tostring(self._p)
end

end

return setmetatable({
  _NAME      = "rs232";
  _VERSION   = "0.1.1-dev";
  _COPYRIGHT = "Copyright (C) 2015-2016 Alexey Melnichuk";
  _LICENSE   = "MIT";

  port  = Port.new;
  error = RS232Error.new;
  ERROR = ERROR;
},{__index = rs232})
