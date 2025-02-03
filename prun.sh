#!/bin/sh

set -eu

# =========================================================================
# ライブラリ部分
# =========================================================================

# 内部変数の初期化
prun_init() {
  PRUN_MAX=${1:-1} PRUN_STATUS='' PRUN_ABORTED=''
  PRUN_PIDS='' PRUN_PIDS_COUNT=0
}

# 最大並列実行数超えないように並列でコマンドを実行する
#   $@: 実行するコマンド
#   中断していたら0以外の終了ステータスを返す
prun() {
  until [ "$PRUN_PIDS_COUNT" -lt "$PRUN_MAX" ]; do
    [ "$PRUN_ABORTED" ] && prun_killall && return 1
    sleep 0.2
    prun_sweep
  done

  # ジョブコントロールを一時的に有効にして実行する
  # 理由:
  #   デフォルトでは非同期プロセスはSIGINTが無視に設定されるため
  #   独立したプロセスグループを作り子プロセス郡を中断しやすくするため
  #   リダイレクトはzshが出力する不要なメッセージを非表示にするため
  set -m
  { (set +m; "$@") >&3 3>&- & } 3>&1 >/dev/null
  set +m

  PRUN_PIDS="${PRUN_PIDS}${PRUN_PIDS:+ }$!"
  PRUN_PIDS_COUNT=$((PRUN_PIDS_COUNT + 1))
}

# 実行を中断する
prun_abort() {
  PRUN_ABORTED=1
}

# すべてのプロセスが終了するのを待つ
#   中断していたら0以外の終了ステータスを返す
prun_wait() {
  while prun_sweep && [ "$PRUN_PIDS_COUNT" -gt 0 ]; do
    [ "$PRUN_ABORTED" ] && prun_killall && return 1
    sleep 0.2
  done
}

# （内部使用）停止したプロセスのクリーンアップ
prun_sweep() {
  eval "set -- $PRUN_PIDS" && PRUN_PIDS='' PRUN_PIDS_COUNT=0
  while [ $# -gt 0 ]; do
    if kill -0 "$1" 2>/dev/null; then
      PRUN_PIDS="${PRUN_PIDS}${PRUN_PIDS:+ }$1"
      PRUN_PIDS_COUNT=$((PRUN_PIDS_COUNT + 1))
    else
      wait "$1"
      PRUN_STATUS="${PRUN_STATUS}${PRUN_STATUS:+ }$1:$?"
    fi
    shift
  done
}

# （内部使用）すべてのプロセスの停止
prun_killall() {
  eval "set -- $PRUN_PIDS"
  while [ $# -gt 0 ]; do
    kill -s INT -- -"$1" 2>/dev/null || :
    shift
  done
}

# =========================================================================
# メイン
# =========================================================================

# 標準入力がパイプのときはDebian ash とNetBSD shでは動作しない
# （FreeBSD shでは動作する）
#   prun.sh: 32: set: Cannot set tty process group (Invalid argument)
#   prun.sh: 32: Cannot set tty process group (Invalid argument)
if [ -p /dev/stdin ]; then
  echo "When stdin is a pipe, not supported in Debian ash and NetBSD sh"
fi

task() {
  r=$((($(od -An -tu1 -N1 /dev/urandom) % 5) + 3))
  echo "task $1: sleep $r"
  sleep "$r"
  echo "task $1: done"
}

# CTRL+Cを押したときの中断処理
trap 'prun_abort' INT

# 初期化（4: 最大並列実行数）
prun_init 4

for n in $(seq 10); do
  # 引数で指定したコマンドを並列で実行する
  # prun sleep 3 || break
  prun task "$n" || break
done

# すべてのプロセスが終了するのを待つ
prun_wait

# 各プロセスのIDと終了ステータスを出力
echo "done: $PRUN_STATUS"

