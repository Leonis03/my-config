#!/usr/bin/env bash
# wayland-ime-smoke.sh -- 判定 WSLg 下原生 Wayland 的 Electron 应用能否使用中文输入法。
#
#   bash tmp/wayland-ime-smoke.sh              # 用 text-input-v1（本机唯一被公布的版本）
#   bash tmp/wayland-ime-smoke.sh 3            # 强行试 v3，复核"没公布就是不行"
#
# 不碰已经在跑的 IDE 实例，用独立 user-data-dir，结束时把 fcitx5 恢复成 X11 模式。
#
# 分四段测，因为三处失败点互相独立，混在一起会把结论归错因：
#   1. 合成器侧 —— Weston 公布了哪些 text_input / input_method 接口
#   2. 输入法侧 —— fcitx5 能不能绑上 input_method
#   3. 应用侧   —— Electron 有没有真的去 bind text_input 并发出 enable 请求
#   4. 人工     —— 敲进去到底出不出中文
#
# 第 2 段必须在没有 fcitx5 守护进程时做：已有实例会让探针在 0.2 秒内退出，
# 根本走不到绑定那一步，于是"没报错"被误读成"绑定成功"。

set -u

IDE=$HOME/opt/antigravity-ide/antigravity-ide
TIV=${1:-1}
# 固定且持久的测试 profile：Google 登录态存在 user-data-dir 里，每次换目录或删目录
# 都要重新登录一次。放 ~/.cache 而不是 /tmp，重启也不丢。要干净环境时 FRESH=1。
DATADIR=$HOME/.cache/antigravity-smoke
LOG=/tmp/agi-ime-smoke.log
PROBE=/tmp/agi-ime-probe.log

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; }
info() { printf '  · %s\n' "$*"; }
hdr()  { printf '\n\033[1m%s\033[0m\n' "$*"; }

[ -x "$IDE" ] || { echo "找不到 $IDE"; exit 2; }

# ---------------------------------------------------------------- 0. 环境
hdr "0. 环境"
info "WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-（未设置）}   DISPLAY=${DISPLAY:-（未设置）}"
[ -n "${WAYLAND_DISPLAY:-}" ] || { bad "没有 Wayland 显示，后面全部无意义"; exit 1; }
IDEVER=$(grep -oE '"version" *: *"[^"]+"' "$HOME/opt/antigravity-ide/resources/app/package.json" 2>/dev/null | head -1 | cut -d'"' -f4)
# Electron 版本只在运行期由 crashpad 的 --annotation=ver= 带出来，离线的包里没有
ELEVER=$(pgrep -af chrome_crashpad_handler 2>/dev/null | grep -oE 'annotation=ver=[0-9.]+' | head -1 | cut -d= -f3)
info "IDE ${IDEVER:-?}  ·  Electron ${ELEVER:-（需有实例在跑才能读到）}"
info "屏幕 $(DISPLAY=${DISPLAY:-:0} xrandr 2>/dev/null | awk '/^Screen/{print $8, $9, $10}' | tr -d ',')"

# ------------------------------------------------- 1+2. 合成器与输入法侧
hdr "1. 合成器能力（Weston 向客户端公布的全局接口）"

FCITX_WAS_RUNNING=0
if pgrep -x fcitx5 >/dev/null; then FCITX_WAS_RUNNING=1; pkill -x fcitx5; sleep 1; fi

WAYLAND_DEBUG=1 timeout 6 fcitx5 >"$PROBE" 2>&1
have() { grep -q "\"$1\"" "$PROBE"; }

if [ "$(wc -l <"$PROBE")" -lt 30 ]; then
  bad "探针日志只有 $(wc -l <"$PROBE") 行，fcitx5 没跑完启动流程；本段结果不可信"
  info "多半是还有 fcitx5 实例在跑。先 pkill -x fcitx5 再重来。"
  exit 1
fi

for i in zwp_text_input_manager_v1 zwp_text_input_manager_v2 zwp_text_input_manager_v3 \
         zwp_input_method_v1 zwp_input_method_manager_v2; do
  if have "$i"; then ok "$i"; else bad "$i  未公布"; fi
done

if ! have zwp_text_input_manager_v1 && ! have zwp_text_input_manager_v3; then
  bad "合成器不提供任何 text-input 协议 → 原生 Wayland 下输入法不可能工作，到此为止"
  exit 1
fi
[ "$TIV" = 3 ] && ! have zwp_text_input_manager_v3 && \
  bad "你要求 v3，但合成器没公布 v3；应用侧会拿不到接口，继续跑只是为了确认这点"

hdr "2. 输入法侧：fcitx5 能否接管 input_method"
if grep -q 'permission to bind input_method denied' "$PROBE"; then
  IM_BOUND=0
  bad "Weston 拒绝绑定 zwp_input_method_v1（error 71），fcitx5 随即整个进程退出"
  info "Weston 把 input_method 保留给它自己拉起的 IME 客户端，而 WSLg 不跑那个客户端。"
  info "注意这不只是「Wayland 输入法不可用」——不加 --disable wayland,waylandim 的话，"
  info "连 X11 侧的输入法都会跟着一起没有。"
else
  IM_BOUND=1
  ok "fcitx5 成功绑定 input_method，链路后半段是通的"
fi

# 恢复守护进程（带 Wayland 模块会被 error 71 拖垮，所以按包装脚本的方式起）
if [ "$FCITX_WAS_RUNNING" = 1 ] || [ "$IM_BOUND" = 0 ]; then
  pgrep -x fcitx5 >/dev/null || { fcitx5 --disable wayland,waylandim -d >/dev/null 2>&1 & sleep 1.5; }
  pgrep -x fcitx5 >/dev/null && ok "fcitx5 守护进程已恢复（X11/DBus 模式，fcitx5-remote=$(fcitx5-remote 2>&1))"
fi

# --------------------------------------------- 3. 应用侧：最优参数开窗口
hdr "3. 启动 IDE（原生 Wayland + 输入法开关全开）"
if [ "${FRESH:-0}" = 1 ]; then
  rm -rf "$DATADIR"; info "FRESH=1：已清空测试 profile，这次需要重新登录 Google"
elif [ -d "$DATADIR" ]; then
  info "复用测试 profile $DATADIR（登录态保留）"
else
  info "首次创建测试 profile $DATADIR，这一次需要登录 Google，之后不用再登"
fi
info "标志：--ozone-platform=wayland --enable-wayland-ime --wayland-text-input-version=$TIV"
info "环境：XCURSOR_SIZE=24（修 Wayland 下光标过大） + GTK/QT_IM_MODULE + XMODIFIERS"

WAYLAND_DEBUG=1 \
DONT_PROMPT_WSL_INSTALL=1 \
XCURSOR_SIZE=24 \
GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
setsid "$IDE" \
  --ozone-platform=wayland \
  --enable-wayland-ime \
  --wayland-text-input-version="$TIV" \
  --user-data-dir="$DATADIR" \
  >"$LOG" 2>&1 &

info "等窗口起来…"; sleep 20

if grep -q "zwp_text_input_manager_v$TIV" "$LOG"; then
  ok "Electron 拿到了 zwp_text_input_manager_v$TIV"
else
  bad "Electron 没拿到 zwp_text_input_manager_v$TIV"
fi

# text_input.enable 只在输入框获得焦点时才发出，所以必须等人点进去
hdr "4. 人工验收 —— 现在去那个新窗口里操作"
info "1) 点进右侧 Agent 的输入框（或随便打开一个文件）"
info "2) 按 Ctrl+Space 或 左Shift 切中文，试着打字"
if [ -t 0 ]; then
  printf '  · 做完按回车继续…'; read -r _
else
  info "（非交互环境，等 45 秒）"; sleep 45
fi

hdr "5. 判决"
if grep -qE 'zwp_text_input_v[0-9]+@[0-9]+\.(enable|activate)' "$LOG"; then
  ok "应用侧确实发出了 text_input enable/activate —— Electron 这边没问题"
  APP=1
else
  bad "应用侧从未发出 text_input 请求（焦点进了输入框也没有）"
  APP=0
fi

if [ "$IM_BOUND" = 0 ]; then
  bad "链路断在 合成器 ↔ 输入法 之间：应用就算申请了输入法，Weston 也没有输入法可转发。"
  info "这不是配置问题，是 WSLg 的 Weston 不允许第三方 IME 绑定 input_method。"
  info "→ 原生 Wayland 下用不了中文输入法，结论为真。留在 --ozone-platform=x11。"
elif [ "$APP" = 1 ]; then
  info "两侧都通。若仍打不出中文，问题在 fcitx5 配置或协议版本，可换 v$([ "$TIV" = 1 ] && echo 3 || echo 1) 再试。"
else
  info "合成器与输入法侧都通，但应用没发请求 —— 换 text-input 版本再试一次。"
fi

echo
info "全量日志 $LOG  ·  探针 $PROBE"
info "清理：pkill -f 'user-data-dir=$DATADIR'   （profile 保留，下次免登录）"
