"""Scripts/bump_version.py 的测试：python3 -m unittest discover -s Scripts"""

import contextlib
import io
import os
import subprocess
import tempfile
import unittest

import bump_version


class VersionPolicyTests(unittest.TestCase):
    def assertBump(self, messages, expected):
        for message in messages:
            with self.subTest(message=message):
                self.assertEqual(bump_version.version_bump_for_commit(message), expected)

    def test_feature_commits_bump_minor_and_reset_patch(self):
        self.assertBump([
            "feat: 用可调图标尺寸和间距替代扇区偏好",
            "feat(settings): 新增圈间距、手柄样式与背景样式配置",
            "remove: 删除旧的扇区偏好",
            "enhance: 增强悬浮条拖动",
            "删除: 移除旧的场景代理",
            "新增功能: 支持拖到四个角落",
        ], bump_version.FEATURE)
        self.assertEqual(bump_version.next_version("1.2.3+45", bump_version.FEATURE), "1.3.0+46")

    def test_fixes_and_refactors_bump_patch(self):
        self.assertBump([
            "fix(ios): stop HUD child via root persona stopper",
            "fix(KSBallSettings): 将最小手柄触控半径从 16 降至 4",
            "refactor(KSBall): 移除场景代理并改用系统 HUD 进程模型",
            "优化: 调整扇形菜单展开动画",
            "",
        ], bump_version.BUG_FIX)
        self.assertEqual(bump_version.next_version("1.3.0+46", bump_version.BUG_FIX), "1.3.1+47")

    def test_build_changes_only_bump_build(self):
        self.assertBump([
            "ci: 调整版本号递增逻辑",
            "chore: bump build metadata to 1.3.1+47 [skip ci]",
            "docs: 补充 TrollStore 安装说明",
            "test: 增加版本策略测试",
            "fix: 修复 Xcode 编译失败",
            "fix(ci): 修复 ldid 签名缺少 entitlement",
            "fix: 修复悬浮条闪烁 [no-version]",
            "feat: 调整发布流程 [build-fix]",
        ], bump_version.BUILD_ONLY)
        self.assertEqual(bump_version.next_version("1.3.1+47", bump_version.BUILD_ONLY), "1.3.1+48")

    def test_multiple_commits_use_largest_bump(self):
        self.assertEqual(bump_version.version_bump_for_commits(["docs: 更新说明", "fix: 修复拖动", "feat: 新增搜索"]), bump_version.FEATURE)
        self.assertEqual(bump_version.version_bump_for_commits(["ci: 缓存依赖", "fix: 修复拖动"]), bump_version.BUG_FIX)
        self.assertEqual(bump_version.version_bump_for_commits([]), bump_version.BUILD_ONLY)

    def test_malformed_versions_are_rejected(self):
        for version in ("1.0", "1.0.0", "1.0.0+b1", "v1.0.0+1"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                bump_version.next_version(version, bump_version.BUG_FIX)


class InfoPlistTests(unittest.TestCase):
    PLIST = (
        "<dict>\r\n"
        "    <key>CFBundleShortVersionString</key>\r\n"
        "    <string>1.2.3</string>\r\n"
        "    <key>CFBundleVersion</key>\r\n"
        "    <string>45</string>\r\n"
        "</dict>\r\n"
    )

    def test_version_round_trip_keeps_formatting(self):
        self.assertEqual(bump_version.read_version(self.PLIST), "1.2.3+45")
        updated = bump_version.write_version(self.PLIST, "1.3.0+46")
        self.assertEqual(updated, self.PLIST.replace("1.2.3", "1.3.0").replace(">45<", ">46<"))

    def test_main_bumps_and_sets_version_in_place(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "Info.plist")
            with open(path, "w", encoding="utf-8", newline="") as file:
                file.write(self.PLIST)

            def run(*arguments):
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    bump_version.main([*arguments, "--plist", path])
                return output.getvalue().strip()

            self.assertEqual(run(), "1.2.3+45")
            self.assertEqual(run("--auto", "--commit-message", "fix: 修复拖动", "--commit-message", "feat: 新增搜索"), "1.3.0+46")
            self.assertEqual(run("--build-only"), "1.3.0+47")
            self.assertEqual(run("--set", "2.0.0+100"), "2.0.0+100")
            self.assertEqual(run(), "2.0.0+100")

    def test_repository_info_plist_uses_supported_format(self):
        with open(bump_version.INFO_PLIST, encoding="utf-8", newline="") as file:
            bump_version.read_version(file.read())


class PendingCommitTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.repository = directory.name
        self.git("init", "-q")
        self.git("config", "user.name", "KSBall Tests")
        self.git("config", "user.email", "tests@example.com")
        self.git("config", "commit.gpgsign", "false")

    def git(self, *arguments):
        return subprocess.run(["git", *arguments], cwd=self.repository, check=True, capture_output=True, text=True, encoding="utf-8").stdout.strip()

    def commit(self, message):
        self.git("commit", "-q", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD")

    def pending(self):
        return bump_version.pending_commit_messages(cwd=self.repository)

    def test_only_commits_after_latest_bump_are_pending(self):
        self.commit("feat: 新增扇形菜单")
        self.assertEqual(self.pending(), ["feat: 新增扇形菜单"])
        self.commit("chore: bump build metadata to 1.1.0+2 [skip ci]")
        self.assertEqual(self.pending(), [])
        self.commit("fix: 修复拖动")
        self.commit("docs: 更新说明")
        self.assertEqual(self.pending(), ["docs: 更新说明", "fix: 修复拖动"])

    def test_merged_bump_commit_still_bounds_pending_commits(self):
        # 本地提交后用 merge 方式拉取 CI 的递增提交，已计入版本的功能提交不能再算一次。
        feature = self.commit("feat: 新增扇形菜单")
        bump = self.commit("chore: bump build metadata to 1.1.0+2 [skip ci]")
        self.git("checkout", "-q", "-b", "local", feature)
        self.commit("fix: 修复拖动")
        self.git("merge", "-q", "--no-edit", bump)
        messages = self.pending()
        self.assertIn("fix: 修复拖动", messages)
        self.assertNotIn("feat: 新增扇形菜单", messages)
        self.assertEqual(bump_version.version_bump_for_commits(messages), bump_version.BUG_FIX)


if __name__ == "__main__":
    unittest.main()
