import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class TestLfs2nMountSplit(unittest.TestCase):
    def test_lfs2n_has_own_little_flash_adapter(self):
        adapter = ROOT / "components" / "luat_lfs2_nand" / "luat_lfs2_nand_little_flash_lfs2.c"
        self.assertTrue(adapter.exists(), "lfs2_nand adapter file must exist")
        content = adapter.read_text(encoding="utf-8")
        self.assertIn("luat_lfs2_nand_flash_lfs_lf", content)
        self.assertIn("luat_lfs2n_block_profile_reset", content)

    def test_profile_layer_uses_lfs2n_symbols(self):
        profile = ROOT / "components" / "luat_lfs2_nand" / "luat_fs_lfs2_nand_profile.c"
        content = profile.read_text(encoding="utf-8")
        self.assertIn("luat_lfs2_nand_flash_lfs_lf", content)
        self.assertIn("luat_lfs2n_block_profile_reset", content)
        self.assertIn("luat_lfs2n_block_profile_log", content)
        self.assertIn('#define NAND_FS_NAME "lfsn"', content)

    def test_little_flash_router_uses_lfsn_selector(self):
        router = ROOT / "components" / "little_flash" / "luat_lib_little_flash.c"
        content = router.read_text(encoding="utf-8")
        self.assertIn('strcmp(fs, "lfsn") == 0', content)


if __name__ == "__main__":
    unittest.main()
