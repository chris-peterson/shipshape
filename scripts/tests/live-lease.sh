# Sourced by the suites that need a lease naming a live process. The test shell
# itself is that process; its lease takes the form Claude Code writes on this
# platform: {"pid","procStart"} from `ps`, or under git-bash, where `ps` can't
# report a start time, {"pid","procStartFt"} for the shell's Windows pid.

if [ -n "$(ps -p $$ -o lstart= 2>/dev/null || true)" ]; then
  LEASE_DIALECT=posix
  LIVE_PID=$$
  LIVE_START=$(ps -p $$ -o lstart= | sed 's/^ *//;s/ *$//')
  live_lease() { printf '{"pid":%s,"procStart":"%s"}' "$LIVE_PID" "$LIVE_START"; }
  recycled_lease() { printf '{"pid":%s,"procStart":"Mon Jan 01 00:00:00 2020"}' "$LIVE_PID"; }
else
  LEASE_DIALECT=windows
  LIVE_PID=$(cat "/proc/$$/winpid")
  LIVE_START=$(powershell.exe -NoProfile -NonInteractive -Command \
    "(Get-Process -Id $LIVE_PID).StartTime.ToFileTimeUtc()" | tr -d '\r')
  live_lease() { printf '{"pid":%s,"procStartFt":"%s"}' "$LIVE_PID" "$LIVE_START"; }
  recycled_lease() { printf '{"pid":%s,"procStartFt":"%s"}' "$LIVE_PID" "$((LIVE_START - 36000000000))"; }
fi
