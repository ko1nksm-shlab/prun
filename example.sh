#!/bin/sh

set -eu

. ./prun.sh

# 標準入力がパイプのときはDebian ash とNetBSD shでは動作しない
# （FreeBSD shでは動作する）
#   prun.sh: 32: set: Cannot set tty process group (Invalid argument)
if [ ! "${PRUN_FIFO:-}" ]; then
  export PRUN_FIFO=1
  [ -e /tmp/fifo ] || mkfifo /tmp/fifo
  cat > /tmp/fifo &
  "$0" "$@" < /tmp/fifo
  rm /tmp/fifo
  exit
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

