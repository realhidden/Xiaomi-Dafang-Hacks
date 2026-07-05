#!/bin/sh

# Included for configure_static_net_iface and get_wifi_mac
. /system/sdcard/scripts/common_functions.sh

CONFIGPATH=/system/sdcard/config
BBOX_BIN=/system/sdcard/bin/busybox

WIFI_IFACE=wlan0
WIFI_LOGFILE=/system/sdcard/log/wifi.log
WIFI_BIN=/system/sdcard/scripts/wifi.sh
WIFI_CONFIG="$CONFIGPATH/wifi.conf"
WIFI_VERBOSE=1

MIN_CONNECT_TIMEOUT=30
MIN_SCAN_INTERVAL=10
MAX_RECONNECT_ATTEMPTS=5
RECONNECT_BASE_DELAY=10

WPA_BIN=/system/bin/wpa_supplicant
WPA_CONFIG="$CONFIGPATH/wpa_supplicant.conf"
WPA_PIDFILE=/var/run/wpa_supplicant.pid

WPA_CLI_BIN=/system/bin/wpa_cli
WPA_CLI_PIDFILE=/var/run/wpa_cli.pid

WPA_ACTION_BIN=/system/sdcard/scripts/wpa_action.sh
WPA_ACTION_PIDFILE=/var/run/wpa_action.pid

HAP_BIN=/system/bin/hostapd
HAP_CONFIG="$CONFIGPATH/hostapd.conf"
HAP_PIDFILE=/var/run/hostapd.pid

UDHCPC_BIN=/sbin/udhcpc
UDHCPC_PIDFILE="/var/run/udhcpc.$WIFI_IFACE.pid"

UDHCPD_BIN=/sbin/udhcpd
UDHCPD_CONFIG="$CONFIGPATH/udhcpd.conf"
UDHCPD_PIDFILE=/var/run/udhcpd.pid

AP_SCANNER_PIDFILE=/var/run/ap_scanner.pid

log() {
  local LEVEL="$1"
  if [ -z "$WIFI_VERBOSE" ] && [ "$LEVEL" = "verbose" ]; then return 0; fi
  shift
  echo "$(date +"%D %T")" "$@" | "$BBOX_BIN" tee -a "$WIFI_LOGFILE"
}

kill_wait() {
  local PIDFILE="$1"
  local PID=$(cat "$PIDFILE")
  log verbose "Killing pid $PID ($PIDFILE)"
  kill "$PID"
  log verbose "Waiting pid $PID ($PIDFILE)"
  wait "$PID"
  log verbose "Removing pidfile $PIDFILE"
  rm -f "$PIDFILE"
}

run_bg() {
  local PIDFILE="$1"
  shift
  "$BBOX_BIN" nohup "$@" 2>&1 >/dev/null &
  echo "$!" > "$PIDFILE"
}

reset_iface() {
  log info "Resetting interface"
  ifconfig "$WIFI_IFACE" down
  ifconfig "$WIFI_IFACE" 0.0.0.0
  ifconfig -a
}

wpa_supplicant_start() {
  log info "Starting wpa_supplicant"
  "$WPA_BIN" -d -B -P "$WPA_PIDFILE" -i "$WIFI_IFACE" -c "$WPA_CONFIG"
}

wpa_supplicant_stop() {
  log info "Stopping wpa_supplicant"
  kill_wait "$WPA_PIDFILE"
}

hostapd_init() {
  if [ -s "$HAP_CONFIG" ]; then return 0; fi
  sed "s/ssid=\(.*\$\)/ssid=\1-$(get_wifi_mac)/" "$HAP_CONFIG.dist" > "$HAP_CONFIG"
}

hostapd_start() {
  log info "Starting hostapd"
  "$HAP_BIN" -d -B -P "$HAP_PIDFILE" "$HAP_CONFIG"
}

hostapd_stop() {
  log info "Stopping hostapd"
  kill_wait "$HAP_PIDFILE"
}

udhcpc_start() {
  local HOSTNAME=$(cat /system/sdcard/cameraname 2>/dev/null || hostname)
  log info "Starting udhcpc (hostname=$HOSTNAME)"
  "$UDHCPC_BIN" -b -p "$UDHCPC_PIDFILE" -i "$WIFI_IFACE" -x hostname:"$HOSTNAME"
}

udhcpc_stop() {
  log info "Stopping udhcpc"
  kill_wait "$UDHCPC_PIDFILE"
}

udhcpd_init() {
  if [ ! -s "$UDHCPD_CONFIG" ]; then
    cp "$UDHCPD_CONFIG.dist" "$UDHCPD_CONFIG"
  fi
}

udhcpd_start() {
  log info "Starting udhcpd"
  "$UDHCPD_BIN" "$UDHCPD_CONFIG"
}

udhcpd_stop() {
  log info "Stopping udhcpd"
  kill_wait "$UDHCPD_PIDFILE"
}

wpa_cli_start() {
  log info "Starting wpa_cli"
  "$WPA_CLI_BIN" -B -P "$WPA_CLI_PIDFILE" -i "$WIFI_IFACE" -a "$WPA_ACTION_BIN"
}

wpa_cli_stop() {
  log info "Stopping wpa_cli"
  kill_wait "$WPA_CLI_PIDFILE"
}

wpa_action_connected() {
  log info "Connected"
  wpa_action_watchdog_stop
}

wpa_action_disconnected() {
  log info "Disconnected"
  wpa_action_watchdog_stop
  wpa_action_watchdog_start
}

wifi_get_signal_strength() {
  local RESULT=$("$WPA_CLI_BIN" -i "$WIFI_IFACE" SIGNAL_POLL 2>/dev/null)
  echo "$RESULT" | grep "SIGNAL=" | cut -d= -f2
}

wifi_check_connection() {
  local STATUS=$("$WPA_CLI_BIN" -i "$WIFI_IFACE" status 2>/dev/null)
  echo "$STATUS" | grep "wpa_state=COMPLETED" >/dev/null 2>&1
}

wpa_action_watchdog() {
  local TIMEOUT="$(get_config "$WIFI_CONFIG" connect_timeout)"
  if [ -z "$TIMEOUT" ] || [ "$TIMEOUT" -lt "$MIN_CONNECT_TIMEOUT" ]; then
    TIMEOUT="$MIN_CONNECT_TIMEOUT"
  fi
  log verbose "wpa_action watchdog sleeping $TIMEOUT seconds"
  sleep "$TIMEOUT"

  if wifi_check_connection; then
    local SIGNAL=$(wifi_get_signal_strength)
    log info "WiFi connected (signal: ${SIGNAL:-unknown}%)"
    rm -f "$WPA_ACTION_PIDFILE"
    return 0
  fi

  log info "WiFi not connected after ${TIMEOUT}s, attempting reconnect"

  local ATTEMPT=0
  while [ "$ATTEMPT" -lt "$MAX_RECONNECT_ATTEMPTS" ]; do
    ATTEMPT=$((ATTEMPT + 1))
    local DELAY=$((RECONNECT_BASE_DELAY * ATTEMPT))
    log info "Reconnect attempt $ATTEMPT/$MAX_RECONNECT_ATTEMPTS (waiting ${DELAY}s)"
    sleep "$DELAY"

    reset_iface
    sleep 2
    wpa_supplicant_start
    sleep 5

    if wifi_check_connection; then
      local SIGNAL=$(wifi_get_signal_strength)
      log info "Reconnected on attempt $ATTEMPT (signal: ${SIGNAL:-unknown}%)"
      rm -f "$WPA_ACTION_PIDFILE"
      return 0
    fi
  done

  log info "Failed to reconnect after $MAX_RECONNECT_ATTEMPTS attempts, switching to AP mode"
  rm -f "$WPA_ACTION_PIDFILE"
  exec "$WIFI_BIN" ap
}

wpa_action_watchdog_start() {
  log info "Starting wpa_action watchdog"
  run_bg "$WPA_ACTION_PIDFILE" "$WIFI_BIN" wpa_action watchdog
}

wpa_action_watchdog_stop() {
  log info "Stopping wpa_action watchdog"
  kill_wait "$WPA_ACTION_PIDFILE"
}

ap_scanner_ssid() {
  grep -v '^[[:space:]]*#' "$WPA_CONFIG" | grep "ssid=" | cut -d "=" -f2
}

ap_scanner_scan() {
  iwlist "$WIFI_IFACE" scanning | grep '^[[:space:]]*ESSID:' | grep -v '""' | cut -d ":" -f2
}

ap_scanner() {
  while true; do
    local INTERVAL="$(get_config "$WIFI_CONFIG" scan_interval)"
    if [ -z "$INTERVAL" ] || [ "$INTERVAL" -lt "$MIN_SCAN_INTERVAL" ]; then
      INTERVAL="$MIN_SCAN_INTERVAL"
    fi
    log verbose "ap_scanner sleeping $INTERVAL seconds"
    sleep "$INTERVAL"
    local SSID="$(ap_scanner_ssid)"
    if [ -z "$SSID" ] && [ "$SSID" != '""' ]; then
      log verbose "ap_scanner has no ssid, skipping scan"
      continue
    fi
    local SCAN="$(iwlist "$WIFI_IFACE" scanning 2>/dev/null | grep 'ESSID:' | grep -v '""')"
    if [ -z "$SCAN" ]; then
      log verbose "ap_scanner found no networks"
      continue
    fi
    if echo "$SCAN" | grep -q "$SSID"; then
      local STRENGTH=$(echo "$SCAN" | grep "$SSID" | grep -oE 'Signal level=[-0-9]+' | head -1 | cut -d= -f2)
      log info "ap_scanner found $SSID (signal: ${STRENGTH:-unknown}dBm)"
      rm -f "$AP_SCANNER_PIDFILE"
      log info "Switching to station mode"
      exec "$WIFI_BIN" station
    else
      log verbose "ap_scanner: configured SSID '$SSID' not found in scan results"
    fi
  done
}

ap_scanner_start() {
  log info "Starting ap_scanner"
  run_bg "$AP_SCANNER_PIDFILE" "$WIFI_BIN" ap_scanner
}

ap_scanner_stop() {
  log info "Stopping ap_scanner"
  kill_wait "$AP_SCANNER_PIDFILE"
}

station_ifup() {
  if [ -s "$CONFIGPATH/staticip.conf" ]; then
    configure_static_net_iface "$WIFI_IFACE"
  else
    ifconfig "$WIFI_IFACE" up
    udhcpc_start
  fi
}

station_start() {
  log info "Starting station mode"
  ap_stop
  wpa_supplicant_start
  wpa_action_watchdog_start
  wpa_cli_start
  station_ifup
}

station_stop() {
  log info "Stopping station mode"
  wpa_action_watchdog_stop
  wpa_cli_stop
  udhcpc_stop
  wpa_supplicant_stop
  reset_iface
}

ap_ifup() {
  local IP="$(grep router "$UDHCPD_CONFIG" | cut -d ' ' -f3)"
  local NETMASK="$(grep subnet "$UDHCPD_CONFIG" | cut -d ' ' -f3)"
  ifconfig "$WIFI_IFACE" up "$IP" netmask "$NETMASK"
}

ap_start() {
  log info "Starting access point mode"
  station_stop
  hostapd_start
  ap_ifup
  udhcpd_start
  ap_scanner_start
}

ap_stop() {
  log info "Stopping access point mode"
  ap_scanner_stop
  udhcpd_stop
  hostapd_stop
  reset_iface
}

wifi_init() {
  hostapd_init
  udhcpd_init
  if [ ! -s "$WIFI_CONFIG" ]; then
    cp "$WIFI_CONFIG.dist" "$WIFI_CONFIG"
  fi
}

wifi_start() {
  log info "Starting wifi"
  wifi_init
  if [ -s "$WPA_CONFIG" ]; then
    station_start
  else
    ap_start
  fi
}

case $1 in
  start)
    wifi_start
    ;;
  ap|station)
    "$1_start"
    ;;
  wpa_action)
    "$1_$2"
    ;;
  ap_scanner)
    "$1"
    ;;
esac
