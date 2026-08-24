#!/usr/bin/env bash
# 跑全部测试：根项目 + 各本地包。
#
# 背景：bili_api 从 lib/app/services/bili/ 拆成了 packages/bili_api 独立包
# （media_cache 同理，从 lib/app/services/ 下的缓存/代理/标签探测代码拆出）
# 之后，它们的 test/ 不再被根目录的 `flutter test` 收进去（Flutter 的 test
# runner 只扫自己 pubspec 所在目录下的 test/，不会递归进 path 依赖）。
# 光跑根 `flutter test` 看到全绿，其实是包里的用例根本没跑，是假绿。
#
# 用法：
#   tool/test_all.sh       依次跑根项目和每个包的测试，任何一个失败就退出码 1

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

fail=0

run() {
  local label="$1"
  local dir="$2"
  echo "==> $label"
  (cd "$dir" && flutter test)
  if [[ $? -ne 0 ]]; then
    echo "✗ $label 失败"
    fail=1
  else
    echo "✓ $label 通过"
  fi
  echo
}

run "根项目" "."
run "packages/bili_api" "packages/bili_api"
run "packages/media_cache" "packages/media_cache"

if (( fail )); then
  echo "有测试套件失败，见上面的输出。"
  exit 1
fi

echo "全部测试套件通过。"
