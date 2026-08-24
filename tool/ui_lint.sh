#!/usr/bin/env bash
# UI 规范门禁：扫描 lib/ 下的设计 token 违规，与基线比对。
#
# 用法：
#   tool/ui_lint.sh              与基线比对，有任何一项变多就退出码 1
#   tool/ui_lint.sh --update     把当前值写回基线（还完一批债之后跑）
#   tool/ui_lint.sh --report     只打印当前值，不比对
#
# 设计意图：存量欠账可以慢慢还，但**新债一分不欠**。所以门禁只看"是否变多"，
# 不要求归零——要求归零的门禁在存量代码里只会被 --no-verify 绕过。
#
# 移植自 flutter_template 的 tool/ui_lint.sh，本仓库做了三处调整：
# 1. ripgrep 在这台机器上不一定在 PATH 上，显式探测并允许 RG=... 覆盖。
# 2. 基线文件按 LF 读取（见下方 CRLF 处理 + .gitattributes），避免
#    git-bash 下 CRLF 混进数值导致 `(( cur > base ))` 算术出错。
# 3. 指标集合按本仓库实际情况取舍：去掉 material_icons（这个 App 到处用
#    Icons.*，基线几百年不会变，纯噪音）和 raw_avatar（没有对应的公共组件
#    可对比）；新增 edge_insets / sized_box_numeric 两个高频散值指标。

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1
LIB="lib"
BASELINE="tool/ui_lint_baseline.txt"

RG=${RG:-$(command -v rg || echo "$HOME/Documents/Codex/tools/rg/rg")}
[[ -x "$RG" ]] || { echo "需要 ripgrep，装一个或用 RG=/path/to/rg 指定" >&2; exit 2; }

# 图标映射表是代码生成物，不算违规现场
EXCLUDE=(--glob '!**/phosphor_icons_map.dart')

# 这些目录按设计就该出现"违规"写法：token 定义处本身、组件层内部实现
# （公共组件就是 token 的包装层）、以及第三方 vendored 代码。
# 注意：不对 lib/pages/player/** 开白名单——它是欠债最多的页面，正需要
# 门禁施压，开了白名单等于放弃这块债。
ALLOW=(--glob '!**/app/theme/**' --glob '!**/components/**' --glob '!**/plugins/**')

count() {
  "$RG" -c --pcre2 --no-filename "${@:2}" "$1" "$LIB" "${EXCLUDE[@]}" "${ALLOW[@]}" 2>/dev/null \
    | awk '{s+=$1} END {print s+0}'
}

measure() {
  echo "fontSize=$(count 'fontSize:\s*[0-9]')"
  echo "edge_insets=$(count 'EdgeInsets\.(all|symmetric|only|fromLTRB)\(')"
  echo "sized_box_numeric=$(count 'SizedBox\((height|width):\s*[0-9]')"
  echo "raw_radius=$(count 'BorderRadius\.circular\(')"
  echo "hardcoded_color=$(count 'Color\(0x')"
  echo "colors_white_black=$(count 'Colors\.(white|black|grey)')"
  echo "raw_appbar=$(count 'appBar:\s*AppBar\(')"
  echo "raw_alert_dialog=$(count 'AlertDialog\(')"
  echo "raw_snackbar=$(count 'showSnackBar\(')"
  echo "raw_switch=$(count '\b(SwitchListTile|CupertinoSwitch)\(')"
}

case "${1:-}" in
  --report) measure; exit 0 ;;
  --update) measure > "$BASELINE"; echo "基线已更新 → $BASELINE"; cat "$BASELINE"; exit 0 ;;
esac

if [[ ! -f "$BASELINE" ]]; then
  echo "没有基线文件，先跑一次：tool/ui_lint.sh --update" >&2
  exit 1
fi

fail=0
while IFS='=' read -r key base; do
  base=${base%$'\r'}
  key=${key%$'\r'}
  [[ -z "$key" ]] && continue
  cur=$(measure | grep "^$key=" | cut -d= -f2)
  if (( cur > base )); then
    printf '✗ %-20s %s → %s  (+%s)\n' "$key" "$base" "$cur" "$((cur - base))"
    fail=1
  elif (( cur < base )); then
    printf '✓ %-20s %s → %s  (-%s)\n' "$key" "$base" "$cur" "$((base - cur))"
  fi
done < "$BASELINE"

if (( fail )); then
  echo
  echo "有指标变多了。新代码请走 lib/app/theme/tokens.dart 的 token，"
  echo "确实是合理例外的话，把该文件加进本脚本的白名单。"
  exit 1
fi

echo "UI 门禁通过（没有新增违规）。"
