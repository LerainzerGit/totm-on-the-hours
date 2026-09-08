#!/usr/bin/env bash
###############################################################################
# TOTM: On the Hours — build_playlist.sh
#
# Scans playlist/episodes/ and generates playlist/playlist.m3u in FFmpeg
# "concat demuxer" format, e.g.:
#
#   file 'episodes/some_episode_title.mp4'
#   file 'episodes/another_episode.mp4'
#
# The resulting file is consumed directly by scripts/start_stream.sh via:
#   ffmpeg -re -stream_loop -1 -i playlist/playlist.m3u ...
###############################################################################
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PLAYLIST_DIR="${REPO_ROOT}/playlist"
EPISODES_DIR="${PLAYLIST_DIR}/episodes"
PLAYLIST_FILE="${PLAYLIST_DIR}/playlist.m3u"
TMP_FILE="$(mktemp)"

mkdir -p "${EPISODES_DIR}"

echo "[build_playlist] Scanning ${EPISODES_DIR} ..."

# ---------------------------------------------------------------------------
# Collect episode files (mp4/mkv/webm/m4v), sorted for a stable, predictable
# channel order. Filenames are single-quoted per the FFmpeg concat demuxer
# spec; any literal single quote in a filename is escaped as '\'' .
# ---------------------------------------------------------------------------
{
  echo "# TOTM: On the Hours — auto-generated playlist"
  echo "# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  echo "# Do not edit by hand — regenerate with scripts/build_playlist.sh"
  echo "ffconcat version 1.0"
} > "${TMP_FILE}"

FOUND_ANY=0
while IFS= read -r -d '' filepath; do
  FOUND_ANY=1
  filename="$(basename "${filepath}")"
  escaped="${filename//\'/\'\\\'\'}"
  echo "file 'episodes/${escaped}'" >> "${TMP_FILE}"
done < <(find "${EPISODES_DIR}" -maxdepth 1 -type f \
            \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' -o -iname '*.m4v' \) \
            -print0 | sort -z)

if [ "${FOUND_ANY}" -eq 0 ]; then
  echo "[build_playlist] WARNING: no episode files found in ${EPISODES_DIR}." >&2
  echo "[build_playlist] Run scripts/fetch_episodes.sh first." >&2
fi

mv "${TMP_FILE}" "${PLAYLIST_FILE}"

ENTRY_COUNT="$(grep -c '^file ' "${PLAYLIST_FILE}" || true)"
echo "[build_playlist] Wrote ${PLAYLIST_FILE} with ${ENTRY_COUNT} entr$( [ "${ENTRY_COUNT}" = "1" ] && echo y || echo ies )."
