# shellcheck shell=sh

prun_maxprocs() {
  PRUN_MAX=$1
}

# 最大並列実行数超えないように並列でコマンドを実行する
#   $@: 実行するコマンド
#   中断していたら0以外の終了ステータスを返す
prun() {
  until [ "$PRUN_PIDS_COUNT" -lt "$PRUN_MAX" ]; do
    [ "$PRUN_ABORTED" ] && prun_interrupt && return 1
    (trap '' TSTP; env sleep 0.3)
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
  prun_interrupt
  PRUN_ABORTED=1
}

# すべてのプロセスが終了するのを待つ
#   中断していたら0以外の終了ステータスを返す
prun_wait() {
  while prun_sweep && [ "$PRUN_PIDS_COUNT" -gt 0 ]; do
    [ "$PRUN_ABORTED" ] && break
    env sleep 0.2
  done
  [ $# -gt 0 ] && eval "$1"='$PRUN_STATE' && PRUN_STATE=''

  [ "$PRUN_ABORTED" ] || return 0
  prun_interrupt
  PRUN_ABORTED=''
  return 1
}

prun_reset() {
  PRUN_STATE='' PRUN_ABORTED='' PRUN_PIDS='' PRUN_PIDS_COUNT=0
}

prun_logger() {
  if [ "${PRUN_LOGGER:-}" ]; then
    echo "$1" >&2
  fi
}

# （内部使用）停止したプロセスのクリーンアップ
# shellcheck disable=SC2120
prun_sweep() {
  eval "set -- $PRUN_PIDS" && PRUN_PIDS='' PRUN_PIDS_COUNT=0
  while [ $# -gt 0 ]; do
    if kill -s 0 "$1" 2>/dev/null; then
      PRUN_PIDS="${PRUN_PIDS}${PRUN_PIDS:+ }$1"
      PRUN_PIDS_COUNT=$((PRUN_PIDS_COUNT + 1))
    else
      wait "$1"
      PRUN_STATE="${PRUN_STATE}${PRUN_STATE:+ }$1:$?"
    fi
    shift
  done
}

prun_interrupt() {
  prun_logger "prun_interrupt"
  prun_signal INT
}

prun_suspend() {
  prun_logger "prun_suspend"
  prun_signal TSTP
}

prun_resume() {
  prun_logger "prun_resume"
  prun_signal CONT
}

# （内部使用）すべてのプロセスにシグナルを送信
# shellcheck disable=SC2120
prun_signal() {
  eval "set -- $PRUN_PIDS -s $1 --"
  until [ "$1" = -s ]; do
    set -- "$@" "-$1"
    shift
  done
  kill "$@" 2>/dev/null || :
}

prun_reset
