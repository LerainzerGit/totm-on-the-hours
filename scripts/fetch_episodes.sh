#!/usr/bin/env bash
###############################################################################
# TOTM: On the Hours — fetch_episodes.sh
#
# Downloads all videos from @YellowWorldTOTMU into playlist/episodes/ using
# yt-dlp. Safe to run repeatedly: yt-dlp's --download-archive prevents
# duplicate downloads, and the archive file is committed alongside the
# episodes so re-runs (locally, in CI, or on a self-hosted runner) never
# re-fetch content that's already present.
###############################################################################
set -euo pipefail

# ---------------------------------------------------------------------------
# Paths (resolved relative to repo root, regardless of caller's cwd)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

EPISODES_DIR="${REPO_ROOT}/playlist/episodes"
ARCHIVE_FILE="${EPISODES_DIR}/.download-archive.txt"
CHANNEL_URL="https://www.youtube.com/@YellowWorldTOTMU"

mkdir -p "${EPISODES_DIR}"
touch "${ARCHIVE_FILE}"

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
if ! command -v yt-dlp >/dev/null 2>&1; then
  echo "[fetch_episodes] ERROR: yt-dlp is not installed or not on PATH." >&2
  echo "[fetch_episodes] Install with: pip install -U yt-dlp" >&2
  exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
  echo "[fetch_episodes] WARNING: ffmpeg not found. yt-dlp needs it for" >&2
  echo "[fetch_episodes] merging/remuxing formats; downloads may fail." >&2
fi

echo "[fetch_episodes] Channel : ${CHANNEL_URL}"
echo "[fetch_episodes] Target  : ${EPISODES_DIR}"
echo "[fetch_episodes] Archive : ${ARCHIVE_FILE}"

# ---------------------------------------------------------------------------
# Download
#
#   --download-archive   : skip anything already recorded (idempotent)
#   --no-overwrites       : never clobber an existing file
#   --continue             : resume partial downloads
#   --ignore-errors        : one broken video shouldn't kill the whole run
#   --restrict-filenames   : filesystem/playlist-safe filenames
#   -f mp4-friendly format : consistent container for the FFmpeg loop later
# ---------------------------------------------------------------------------
yt-dlp \
  --download-archive "${ARCHIVE_FILE}" \
  --no-overwrites \
  --continue \
  --ignore-errors \
  --restrict-filenames \
  --retries 5 \
  --fragment-retries 5 \
  -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best" \
  --merge-output-format mp4 \
  -o "${EPISODES_DIR}/%(title)s.%(ext)s" \
  "${CHANNEL_URL}"

DOWNLOADED_COUNT="$(find "${EPISODES_DIR}" -maxdepth 1 -type f -name '*.mp4' | wc -l | tr -d ' ')"
echo "[fetch_episodes] Done. ${DOWNLOADED_COUNT} episode(s) currently on disk."
