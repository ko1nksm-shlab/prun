#!/bin/sh

set -eu

PRUN_LOGGER=1

. ./prun.sh
PRUN_ENABLE_SH_WORKAROUND=1
prun_init "$0" "$@"

task() {
  trap "echo task $1: int" INT
  r=$((($(dd if=/dev/urandom 2>/dev/null | od -An -tu1 -N1) % 5) + 3))
  echo "task $1: sleep $r"
  env sleep "$r"
  echo "task $1: done"
}

# CTRL+Cを押したときの中断処理
cleanup() {
  trap '' HUP INT QUIT PIPE TERM
  prun_abort
  trap - EXIT "$1"
  [ "$1" = EXIT ] || prun_logger "kill self: $1"
  [ "$1" = EXIT ] || kill -s "$1" $$ || exit 1
}

for i in EXIT HUP INT QUIT PIPE TERM; do
  trap 'cleanup '"$i" "$i"
done

suspend() {
  prun_suspend
  kill -s STOP $$ || exit 1
}

resume() {
  prun_resume
}

if (trap : TSTP && trap : CONT) 2>/dev/null; then
  trap 'suspend' TSTP
  trap 'resume' CONT
fi

# 初期化（4: 最大並列実行数）
prun_maxprocs 4

for n in $(seq 10); do
  # 引数で指定したコマンドを並列で実行する
  # prun sleep 3 || break
  prun task "$n" || break
done

# すべてのプロセスが終了するのを待つ
prun_wait state

# 各プロセスのIDと終了ステータスを出力
echo "done: $state"

