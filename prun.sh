# shellcheck shell=sh

prun_maxprocs() {
  PRUN_MAX=$1
}

# 最大並列実行数超えないように並列でコマンドを実行する
#   $@: 実行するコマンド
#   中断していたら0以外の終了ステータスを返す
prun() {
  until [ "$PRUN_PIDS_COUNT" -lt "$PRUN_MAX" ]; do
    [ "$PRUN_ABORTED" ] && prun_killall && return 1
    env sleep 0.2
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
  prun_killall
  PRUN_ABORTED=1
}

# すべてのプロセスが終了するのを待つ
#   中断していたら0以外の終了ステータスを返す
prun_wait() {
  [ $# -gt 0 ] && eval "$1"='$PRUN_STATE' && PRUN_STATE=''
  while prun_sweep && [ "$PRUN_PIDS_COUNT" -gt 0 ]; do
    [ "$PRUN_ABORTED" ] && break
    env sleep 0.2
  done

  [ "$PRUN_ABORTED" ] || return 0
  prun_killall
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

# （内部使用）すべてのプロセスの停止
# shellcheck disable=SC2120
prun_killall() {
  prun_logger "prun_killall"
  eval "set -- $PRUN_PIDS"
  while [ $# -gt 0 ]; do
    kill -s INT -- -"$1" 2>/dev/null || :
    shift
  done
}

prun_reset
