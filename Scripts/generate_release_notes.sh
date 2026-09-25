#!/usr/bin/env bash
# 生成滚动 Release 的说明：版本号、上一次成功发布以来的提交，以及 commit 与 run 链接。
# 用法：bash Scripts/generate_release_notes.sh <release_tag> <version> <output_file>
# 需要 gh 与 GitHub Actions 提供的 GITHUB_REPOSITORY、GITHUB_SHA、GITHUB_RUN_ID、GITHUB_RUN_NUMBER。
set -euo pipefail

release_tag="${1:?缺少 Release tag}"
version="${2:?缺少应用版本号}"
output_file="${3:?缺少说明输出文件}"
repository="${GITHUB_REPOSITORY:?缺少 GITHUB_REPOSITORY}"
current_sha="${GITHUB_SHA:?缺少 GITHUB_SHA}"

# Release 指向的是上一次成功发布的提交。以它为边界收集提交，
# 这样失败构建后的修复提交仍会和原始功能提交一起出现在说明中。
last_success_sha="$(
  gh release view "$release_tag" \
    --repo "$repository" \
    --json targetCommitish \
    --jq '.targetCommitish' 2>/dev/null || true
)"

commit_shas=()
if [ -n "$last_success_sha" ] && \
  git cat-file -e "${last_success_sha}^{commit}" 2>/dev/null && \
  git merge-base --is-ancestor "$last_success_sha" "$current_sha"; then
  while IFS= read -r commit_sha; do
    if [ -n "$commit_sha" ]; then
      commit_shas+=("$commit_sha")
    fi
  done < <(git rev-list --reverse "${last_success_sha}..${current_sha}")
else
  # 没有可用的历史 Release 时只记录当前提交，避免把整个仓库历史写入说明。
  commit_shas=("$current_sha")
fi

format_commit() {
  local commit_sha="$1"
  local subject
  local body

  subject="$(git show -s --format=%s "$commit_sha")"
  printf '%s\n' "$subject"

  body="$(git show -s --format=%b "$commit_sha" | sed 's/\r$//')"
  if [ -n "$(printf '%s' "$body" | tr -d '[:space:]')" ]; then
    # 提交正文可能已经使用 Markdown 列表，统一归一化为单个短横线。
    printf '%s\n' "$body" | awk '
      {
        line = $0
        sub(/^[[:space:]]+/, "", line)
        sub(/^-[[:space:]]*/, "", line)
        if (line == "") {
          print ""
        } else {
          print " - " line
        }
      }
    '
  fi
  printf '\n'
}

# CI 写回版本号的提交不属于更新内容。
is_build_metadata_commit() {
  local subject="$1"
  [[ "$subject" == chore:\ bump\ build\ metadata* ]]
}

commit_count=0
{
  # 应用从“版本:”一行识别版本号，并把“本次构建包含以下更新：”之后的内容作为更新说明展示。
  printf '版本: %s\n\n' "$version"
  printf '本次构建包含以下更新：\n\n'

  for commit_sha in "${commit_shas[@]}"; do
    subject="$(git show -s --format=%s "$commit_sha")"
    if is_build_metadata_commit "$subject"; then
      continue
    fi
    format_commit "$commit_sha"
    commit_count=$((commit_count + 1))
  done

  # Release 不存在、历史被重写或重复运行同一提交时，至少保留当前提交说明。
  if [ "$commit_count" -eq 0 ]; then
    format_commit "$current_sha"
  fi

  short_sha="${current_sha:0:7}"
  run_url="https://github.com/${repository}/actions/runs/${GITHUB_RUN_ID}"
  commit_url="https://github.com/${repository}/commit/${current_sha}"
  printf 'commit: [%s](%s)\nrun: [%s](%s)\n' \
    "$short_sha" "$commit_url" "${GITHUB_RUN_NUMBER}" "$run_url"
} > "$output_file"
