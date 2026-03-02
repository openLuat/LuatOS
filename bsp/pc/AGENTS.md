# LuatOS PC Simulator

**Scope**: `bsp/pc/` - PC simulator for Windows/Linux/macOS development.

## OVERVIEW

PC simulator allowing LuatOS development and testing on desktop without hardware. Uses SDL2 for GUI simulation.

## STRUCTURE

```
pc/
├── src/              # Simulator-specific code
├── port/             # Platform porting layer
├── include/          # Headers
├── win32/            # Windows-specific
├── ui/               # UI test code
└── xmake.lua         # Build configuration
```

## BUILD

```bash
cd bsp/pc

# Configure
xmake f -a x64 -y        # 64-bit
xmake f -a x86 -y        # 32-bit

# Build
xmake -y

# Output: build/out/luatos-lua.exe
```

## FEATURES

- Lua 5.3 VM execution
- GUI simulation (SDL2)
- Network (via host OS)
- File system (host filesystem)
- Most libraries supported

## WHERE TO LOOK

| Task | Location |
|------|----------|
| Main entry | `src/main.c` |
| Build config | `xmake.lua` |
| Platform port | `port/` |
| UI tests | `ui/` |

## CONVENTIONS

**Adding PC Support:**
- Add files to `src/` or `port/`
- Update `xmake.lua` with platform detection
- Use `#ifdef LUAT_USE_WINDOWS` etc.

## ANTI-PATTERNS

- ❌ Do NOT assume PC == hardware behavior (timing differences)
- ❌ Do NOT hardcode paths - use relative paths
- ❌ Do NOT skip hardware validation phase
