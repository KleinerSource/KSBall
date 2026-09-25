#!/usr/bin/env python3
"""按提交信息递增 KSBall 的版本号，并写回 KSBall/Info.plist。

版本号形如 x.y.z+build：x.y.z 写入 CFBundleShortVersionString，build 写入 CFBundleVersion。
- 新增、删除或增强功能：次版本号 +1，补丁号归零；
- 优化、修复或改进既有行为：补丁号 +1；
- 构建、CI、文档与测试，编译、打包或签名修复，以及标题带 [build-fix] / [no-version] 的提交：只增加 build。
build 每次都 +1。--auto 会读取上一次 CI 版本递增提交之后的全部提交，取其中最大的递增类型。

只依赖 Python 标准库。用法：
  python3 Scripts/bump_version.py                  打印当前版本
  python3 Scripts/bump_version.py --auto           按待发布的提交自动递增
  python3 Scripts/bump_version.py --auto --commit-message "feat: ..."
  python3 Scripts/bump_version.py --feature | --bug-fix | --build-only
  python3 Scripts/bump_version.py --set 1.2.3+45
"""

import argparse
import os
import re
import subprocess
import sys

INFO_PLIST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "KSBall", "Info.plist")
# CI 写回版本号时使用的提交标题前缀，也是下一次计算递增类型的起点。
BUILD_METADATA_PREFIX = "chore: bump build metadata"

FEATURE = "feature"
BUG_FIX = "bug-fix"
BUILD_ONLY = "build-only"
# 按递增幅度从小到大排列，多个提交取最大值。
BUMP_ORDER = (BUILD_ONLY, BUG_FIX, FEATURE)

FEATURE_TYPES = {"feat", "feature", "add", "enhance", "enhancement", "remove", "delete"}
# 没有 Conventional Commits 类型前缀时，按中文描述判断是否为功能变更。
FEATURE_KEYWORDS = ("新增功能", "新增", "添加", "补上", "支持", "实现", "引入", "删除", "移除", "增强")
BUILD_TYPES = {"build", "ci", "chore", "doc", "docs", "test"}
# 修复编译、打包或签名问题不改变应用行为，只增加 build。
BUILD_FIX_KEYWORDS = ("编译", "构建", "打包", "签名", "依赖安装", "xcode", "xcodebuild", "clang", "codesign", "ldid", "workflow")
COMMIT_TYPE_PATTERN = re.compile(r"^([a-z]+)(?:\([^)]*\))?!?:")
VERSION_PATTERN = re.compile(r"^(\d+)\.(\d+)\.(\d+)\+(\d+)$")


def version_bump_for_commit(message):
    """根据单个提交的标题判断版本应如何递增。"""
    lines = message.strip().splitlines()
    subject = lines[0].strip().lower() if lines else ""
    if not subject:
        return BUG_FIX
    if "[build-fix]" in subject or "[no-version]" in subject:
        return BUILD_ONLY

    match = COMMIT_TYPE_PATTERN.match(subject)
    commit_type = match.group(1) if match else None
    if commit_type in FEATURE_TYPES or (commit_type is None and any(keyword in subject for keyword in FEATURE_KEYWORDS)):
        return FEATURE
    if commit_type in BUILD_TYPES:
        return BUILD_ONLY

    is_fix = commit_type == "fix" or subject.startswith("fix ") or "修复" in subject
    if is_fix and any(keyword in subject for keyword in BUILD_FIX_KEYWORDS):
        return BUILD_ONLY
    return BUG_FIX


def version_bump_for_commits(messages):
    """多个提交取最大的递增类型；没有新提交（如重复构建同一提交）时只增加 build。"""
    return max((version_bump_for_commit(message) for message in messages), key=BUMP_ORDER.index, default=BUILD_ONLY)


def next_version(current, bump):
    match = VERSION_PATTERN.match(current.strip())
    if not match:
        raise ValueError(f"版本号不是 x.y.z+build 格式：{current}")
    major, minor, patch, build = (int(part) for part in match.groups())
    if bump == FEATURE:
        minor, patch = minor + 1, 0
    elif bump == BUG_FIX:
        patch += 1
    return f"{major}.{minor}.{patch}+{build + 1}"


def _plist_string_pattern(key):
    return re.compile(r"(<key>" + re.escape(key) + r"</key>\s*<string>)([^<]*)(</string>)")


SHORT_VERSION_PATTERN = _plist_string_pattern("CFBundleShortVersionString")
BUILD_NUMBER_PATTERN = _plist_string_pattern("CFBundleVersion")


def read_version(plist_text):
    short_version = SHORT_VERSION_PATTERN.search(plist_text)
    build_number = BUILD_NUMBER_PATTERN.search(plist_text)
    if not short_version or not build_number:
        raise ValueError("Info.plist 缺少 CFBundleShortVersionString 或 CFBundleVersion")
    version = f"{short_version.group(2).strip()}+{build_number.group(2).strip()}"
    if not VERSION_PATTERN.match(version):
        raise ValueError(f"Info.plist 中的版本号应为 x.y.z 与整数 build，实际为 {version}")
    return version


def write_version(plist_text, version):
    """只替换两个版本字段的值，保留文件其余内容与换行符。"""
    if not VERSION_PATTERN.match(version):
        raise ValueError(f"版本号不是 x.y.z+build 格式：{version}")
    short_version, build_number = version.split("+")
    plist_text = SHORT_VERSION_PATTERN.sub(lambda match: match.group(1) + short_version + match.group(3), plist_text, count=1)
    return BUILD_NUMBER_PATTERN.sub(lambda match: match.group(1) + build_number + match.group(3), plist_text, count=1)


def _git(*arguments, cwd=None):
    return subprocess.run(["git", *arguments], cwd=cwd, check=True, capture_output=True, text=True, encoding="utf-8").stdout


def pending_commit_messages(cwd=None):
    """返回最近一次 CI 版本递增提交之后的全部提交信息（新到旧）；历史中没有递增提交时只取 HEAD。

    用 base..HEAD 取范围，本地用 merge 方式合入 CI 的递增提交后，已计入版本的提交也不会被重复计算。
    """
    base = None
    for line in _git("log", "--topo-order", "--format=%H %s", "HEAD", cwd=cwd).splitlines():
        sha, _, subject = line.partition(" ")
        if subject.startswith(BUILD_METADATA_PREFIX):
            base = sha
            break
    if base is None:
        return [_git("log", "-1", "--format=%B", "HEAD", cwd=cwd).strip()]
    messages = (message.strip() for message in _git("log", "--format=%B%x00", f"{base}..HEAD", cwd=cwd).split("\0"))
    return [message for message in messages if message and not message.startswith(BUILD_METADATA_PREFIX)]


def main(argv=None):
    parser = argparse.ArgumentParser(description="按提交信息递增 KSBall 版本号并写回 Info.plist；不带参数时打印当前版本。")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--auto", action="store_true", help="按上一次 CI 版本递增之后的提交自动判断递增类型")
    mode.add_argument("--feature", action="store_const", const=FEATURE, dest="bump", help="次版本号 +1，补丁号归零")
    mode.add_argument("--bug-fix", action="store_const", const=BUG_FIX, dest="bump", help="补丁号 +1")
    mode.add_argument("--build-only", action="store_const", const=BUILD_ONLY, dest="bump", help="只增加 build")
    mode.add_argument("--set", metavar="VERSION", help="直接写入 x.y.z+build")
    parser.add_argument("--commit-message", action="append", metavar="MESSAGE", help="配合 --auto 使用，代替从 git 读取的提交信息，可重复")
    parser.add_argument("--plist", default=INFO_PLIST, help="要读写的 Info.plist，默认为 KSBall/Info.plist")
    args = parser.parse_args(argv)
    if args.commit_message is not None and not args.auto:
        parser.error("--commit-message 只能与 --auto 一起使用")

    with open(args.plist, encoding="utf-8", newline="") as file:
        plist_text = file.read()
    current = read_version(plist_text)
    if args.set:
        version = args.set.strip()
    elif args.auto:
        messages = args.commit_message if args.commit_message is not None else pending_commit_messages()
        version = next_version(current, version_bump_for_commits(messages))
    elif args.bump:
        version = next_version(current, args.bump)
    else:
        print(current)
        return 0

    updated = write_version(plist_text, version)
    with open(args.plist, "w", encoding="utf-8", newline="") as file:
        file.write(updated)
    print(version)
    return 0


if __name__ == "__main__":
    sys.exit(main())
