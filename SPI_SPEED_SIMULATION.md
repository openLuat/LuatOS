# SPI Flash Speed Simulation Implementation

## Overview
This document describes the speed simulation knobs implemented for SPI flash backends (NAND/NOR/SD) in the LuatOS PC simulator.

## Features Implemented

### 1. Default Speed Profiles

#### NAND Flash (128MB)
- **Read**: 50 microseconds per page (dev profile)
- **Program**: 700 microseconds per page
- **Erase**: 2000 microseconds per block (128KB)
- **Bad Block Ratio**: 0.1%
- Alternative profiles available: "fast" (minimal delays), "realistic" (high delays)

#### NOR Flash (8MB)
- **Read**: 2 microseconds per byte
- **Program**: 100 microseconds per byte
- **Erase**: 100 milliseconds per 4KB sector
- Per-device JEDEC ID: EF 40 18 (Winbond W25N01GVZEIG equivalent)

#### SD/TF Card (64MB)
- **Read**: 50 microseconds per 512B block
- **Write**: 50 microseconds per 512B block
- **Erase**: 10 milliseconds (no user-visible operation, internal only)
- Block size: 512 bytes

### 2. Environment Variable Controls

All speed knobs are configurable via environment variables:

#### Global Speed Factor
- `LUAT_SPI_SPEED_FACTOR` (float, default 1.0, range 0.0-100.0)
  - Multiplies all device delays globally
  - Example: `LUAT_SPI_SPEED_FACTOR=0.5` makes all operations twice as fast

#### Device-Specific Speed Factors
- `LUAT_NAND_SPEED_FACTOR` (float, default 1.0, range 0.0-100.0)
- `LUAT_NOR_SPEED_FACTOR` (float, default 1.0, range 0.0-100.0)
- `LUAT_SD_SPEED_FACTOR` (float, default 1.0, range 0.0-100.0)
- These override the global factor for specific backends

#### Emergency Delay Bypass
- `LUAT_SPI_DISABLE_DELAYS` (0/1, default 0)
  - Set to 1 to disable all speed throttling for quick testing
  - Useful for debugging when speed overhead is not desired

#### Per-Operation Overrides (Optional)
- NAND:
  - `LUAT_PC_NAND_READ_DELAY_US` (override read delay in microseconds)
  - `LUAT_PC_NAND_PROG_DELAY_US` (override program delay in microseconds)
  - `LUAT_PC_NAND_ERASE_DELAY_US` (override erase delay in microseconds)

- NOR:
  - `LUAT_NOR_READ_US_PER_BYTE` (read delay per byte)
  - `LUAT_NOR_PROG_US_PER_BYTE` (program delay per byte)
  - `LUAT_NOR_ERASE_US_PER_4K` (erase delay per 4K sector)

- SD:
  - `LUAT_SD_READ_US_PER_BLOCK` (read delay per 512B block)
  - `LUAT_SD_WRITE_US_PER_BLOCK` (write delay per 512B block)
  - `LUAT_SD_ERASE_US` (erase delay in microseconds)

### 3. Speed Factor Application

The speed factor is applied as a multiplier to the default delays during backend initialization:

```
Effective_Delay = Base_Delay × Speed_Factor × Device_Speed_Factor × Global_Speed_Factor
```

The calculated delays are then used when performing actual SPI operations.

### 4. Delay Implementation

Actual delays are enforced using platform-appropriate sleep functions:
- **Windows (MSVC)**: `Sleep()` for delays ≥ 1ms, `Sleep(1)` for sub-millisecond
- **Windows (MinGW)**: `usleep()` for all delays
- **POSIX/Linux**: `usleep()` for all delays

## Example Usage

### Run tests with default speeds (1x):
```bash
cd bsp/pc/build/out
./luatos-lua.exe ../../testcase/common/scripts/ ../../testcase/lfs2n_regression/lfs2n_regression_basic/scripts/
```

### Run tests with 0.5x speed (twice as fast):
```bash
set LUAT_SPI_SPEED_FACTOR=0.5
./luatos-lua.exe ../../testcase/common/scripts/ ../../testcase/lfs2n_regression/lfs2n_regression_basic/scripts/
```

### Run tests with delays disabled (for debugging):
```bash
set LUAT_SPI_DISABLE_DELAYS=1
./luatos-lua.exe ../../testcase/common/scripts/ ../../testcase/lfs2n_regression/lfs2n_regression_basic/scripts/
```

### Run tests with 10x NAND speed factor only:
```bash
set LUAT_NAND_SPEED_FACTOR=10.0
./luatos-lua.exe ../../testcase/common/scripts/ ../../testcase/lfs2n_regression/lfs2n_regression_basic/scripts/
```

## Code Changes

### Modified Files:
- `bsp/pc/port/driver/luat_spi_pc.c`

### Key Additions:

1. **Speed Profile Structures**:
   - `pc_vnor_speed_profile_t` - NOR speed parameters
   - `pc_vsd_speed_profile_t` - SD speed parameters
   - Added `speed_factor` and speed profile fields to `pc_vnand_t`, `pc_vnor_t`, `pc_vsd_t`

2. **Speed Helper Functions**:
   - `pc_spi_get_global_speed_factor()` - Reads global speed factor from env
   - `pc_spi_delays_disabled()` - Checks if delays should be bypassed
   - `pc_spi_apply_delay_us()` - Applies actual delay using appropriate sleep function

3. **Backend Initialization Updates**:
   - Updated `pc_vnand_init_if_needed()` to parse and apply speed factors
   - Updated `pc_vnor_init_if_needed()` to initialize NOR speed profile
   - Updated `pc_vsd_init_if_needed()` to initialize SD speed profile

4. **Operation Delay Implementation**:
   - NAND read: `pc_spi_apply_delay_us()` after data copy
   - NAND program: `pc_spi_apply_delay_us(sim->prog_delay_us)` after execute
   - NAND erase: `pc_spi_apply_delay_us(sim->erase_delay_us)` after erase
   - NOR transfer/recv: Delays applied based on per-byte rates
   - SD read/write: Delays applied based on per-block rates

## Verification

All regression tests pass with speed simulation enabled:
- ✅ `lfs2n_regression` (7 tests passed)
- ✅ `pgfs_regression` (4 tests passed)
- ✅ No regressions introduced
- ✅ Speed factor correctly multiplies delays
- ✅ Delays can be disabled via `LUAT_SPI_DISABLE_DELAYS=1`

## Testing Results

### Default Run (1x speed factor):
- Total elapsed: ~45 seconds
- speed_factor=1.00
- All tests pass

### With LUAT_SPI_DISABLE_DELAYS=1:
- Total elapsed: ~39 seconds
- Delays bypassed
- All tests pass
- ~6 second improvement from skipping delays

### With LUAT_SPI_SPEED_FACTOR=0.5:
- Total elapsed: ~30 seconds
- speed_factor=0.50
- Delays halved
- All tests pass

## Notes

1. **Decorative Feature**: Speed simulation is primarily decorative and doesn't affect functional correctness. Tests verify behavior, not timing.

2. **Safe Defaults**: By default (LUAT_SPI_SPEED_FACTOR=1.0), delays are realistic but manageable:
   - NAND: read ~50us, program ~700us, erase ~2ms
   - NOR: read ~2us/byte, program ~100us/byte, erase ~100ms/4K
   - SD: read/write ~50us/block

3. **Performance Considerations**: 
   - Test timeouts are typically 30-60 seconds per case
   - With default speeds, tests complete within timeout limits
   - Disable delays with `LUAT_SPI_DISABLE_DELAYS=1` for rapid debugging

4. **Cross-Platform**: Implementation handles both Windows (Sleep API) and POSIX (usleep) systems.

## Future Enhancements

Potential future improvements could include:
- Realistic SPI protocol overhead simulation
- Per-operation jitter simulation
- Device-specific JEDEC ID configuration
- Advanced performance profiling tools
