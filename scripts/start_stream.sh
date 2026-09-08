#!/usr/bin/env bash
###############################################################################
# TOTM: On the Hours — start_stream.sh
#
# Loops playlist/playlist.m3u forever and pushes it into MediaMTX via RTMP.
# MediaMTX then republishes it as low-latency HLS at:
#   http://localhost:8888/live/totm/index.m3u8
#
# Intended to run under systemd (see systemd/totm-stream.service) so it
# survives crashes and reboots, giving a true 24/7 FAST channel.
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PLAYLIST_FILE="${REPO_ROOT}/playlist/playlist.m3u"
RTMP_URL="rtmp://localhost:1935/live/totm"

if [ ! -s "${PLAYLIST_FILE}" ] || ! grep -q '^file ' "${PLAYLIST_FILE}"; then
  echo "[start_stream] ERROR: ${PLAYLIST_FILE} is missing or empty." >&2
  echo "[start_stream] Run scripts/fetch_episodes.sh then scripts/build_playlist.sh first." >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "[start_stream] ERROR: ffmpeg is not installed or not on PATH." >&2
  exit 1
fi

echo "[start_stream] Streaming ${PLAYLIST_FILE} -> ${RTMP_URL}"
echo "[start_stream] Viewer HLS will be available at http://localhost:8888/live/totm/index.m3u8"

# -re                    : read input at native frame rate (real-time pacing)
# -stream_loop -1        : loop the concat playlist forever
# -fflags +genpts         : regenerate presentation timestamps across loops
# -c:v libx264 / -c:a aac : consistent, broadly-compatible RTMP/HLS codecs
exec ffmpeg -hide_banner -loglevel warning \
  -re \
  -fflags +genpts \
  -stream_loop -1 \
  -f concat -safe 0 \
  -i "${PLAYLIST_FILE}" \
  -c:v libx264 -preset veryfast -tune zerolatency -b:v 4000k -maxrate 4000k -bufsize 8000k \
  -pix_fmt yuv420p -g 60 -keyint_min 60 \
  -c:a aac -b:a 160k -ar 44100 \
  -f flv "${RTMP_URL}"
