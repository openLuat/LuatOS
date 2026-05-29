import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class TestLfs2nLogDefaults(unittest.TestCase):
    def test_lfs2n_profile_logs_default_off(self):
        path = ROOT / "components" / "luat_lfs2_nand" / "luat_fs_lfs2_nand_profile.c"
        content = path.read_text(encoding="utf-8")
        self.assertIn("#define LUAT_LFS2N_DEBUG_LOG 0", content)
        self.assertIn("#define LUAT_LFS2N_PERF_LOG 0", content)

    def test_lfs2n_adapter_trace_logs_default_off(self):
        path = ROOT / "components" / "luat_lfs2_nand" / "luat_lfs2_nand_little_flash_lfs2.c"
        content = path.read_text(encoding="utf-8")
        self.assertIn("#define LUAT_LFS2_IO_TRACE_LOG 0", content)
        self.assertIn("#define LUAT_LFS2_IO_PROFILE_LOG 0", content)

    def test_little_flash_file_restored(self):
        path = ROOT / "components" / "little_flash" / "luat_little_flash_lfs2.c"
        content = path.read_text(encoding="utf-8")
        self.assertIn('#include "lfs.h"', content)
        self.assertIn("lfs_t* flash_lfs_lf", content)

    def test_lua_perf_logs_default_off(self):
        path = (
            ROOT
            / "testcase"
            / "lfs2n_regression"
            / "lfs2n_regression_basic"
            / "scripts"
            / "lfs2n_regression_test.lua"
        )
        content = path.read_text(encoding="utf-8")
        self.assertIn("local LFS2N_DEBUG_LOG_ENABLED = false", content)
        self.assertIn("local LFS2N_PERF_LOG_ENABLED = false", content)


if __name__ == "__main__":
    unittest.main()
