#!/bin/sh

set -eu

. ./prun.sh

# 標準入力がパイプのときはzshでCTRL+Cで停止できない
SELF="$0"
check() {
  [ -t 0 ] && return
  if [ -p "${PRUN_FIFO:-}" ]; then
    exec 0< "$PRUN_FIFO"
    rm "$PRUN_FIFO"
    unset PRUN_FIFO
  else
    PRUN_FIFO=$(mktemp -u)
    mkfifo "$PRUN_FIFO"
    cat > "$PRUN_FIFO" &
    export PRUN_FIFO
    "$SELF" "$@"
    exit
  fi
}
check "$@"

task() {
  trap "echo task $1: int" INT
  r=$((($(od -An -tu1 -N1 /dev/urandom) % 5) + 3))
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

