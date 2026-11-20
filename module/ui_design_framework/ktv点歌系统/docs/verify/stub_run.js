// Runs _stub_test.lua in a fengari Lua 5.3 VM.
const f = require('fengari');
const fs = require('fs');
const lua = f.lua, lauxlib = f.lauxlib, lualib = f.lualib;
const path = process.argv[2];
const L = lua.lua_newstate(null, null);
lualib.luaL_openlibs(L);
const src = fs.readFileSync(path);
if (lauxlib.luaL_loadbuffer(L, src, f.to_luastring(path)) !== lua.LUA_OK) {
  const e = f.to_jsstring(lua.lua_tostring(L, -1));
  console.error('LOAD ERROR:', e);
  process.exit(1);
}
if (lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0) !== lua.LUA_OK) {
  const e = f.to_jsstring(lua.lua_tostring(L, -1));
  console.error('RUNTIME ERROR:', e);
  process.exit(1);
}
