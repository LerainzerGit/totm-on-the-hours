# TOTM: On the Hours

**A 24/7 FAST channel for Talk of the Mock.**

TOTM: On the Hours is a self-hosted, "Free Ad-supported Streaming Television"
(FAST) style channel that loops Talk of the Mock episodes around the clock,
streamed locally via RTMP/HLS and viewable through a browser page powered by
[hls.js](https://github.com/video-dev/hls.js/).

YouTube (@YellowWorldTOTMU)
│ yt-dlp
▼
playlist/episodes/*.mp4
│ build_playlist.sh
▼
playlist/playlist.m3u
│ ffmpeg (-stream_loop -1)
▼
MediaMTX rtmp://localhost:1935/live/totm
│ (remux)
▼
MediaMTX http://localhost:8888/live/totm/index.m3u8 (low-latency HLS)
│ hls.js
▼
docs/index.html (GitHub Pages viewer)


---

## 1. Project overview

| Component        | Role                                                              |
|-------------------|--------------------------------------------------------------------|
| **yt-dlp**         | Downloads episodes from `@YellowWorldTOTMU` into `playlist/episodes/` |
| **build_playlist.sh** | Scans downloaded episodes and writes `playlist/playlist.m3u`     |
| **FFmpeg**         | Loops `playlist.m3u` forever and pushes it into MediaMTX over RTMP |
| **MediaMTX**       | Accepts the RTMP ingest and republishes it as low-latency HLS       |
| **docs/index.html**| A dark-mode hls.js viewer, deployed via GitHub Pages                |
| **GitHub Actions** | Refreshes episodes/playlist on a schedule and deploys the viewer    |
| **systemd**        | Keeps the FFmpeg streaming process alive 24/7 on your host/runner   |

---

## 2. Repository layout

/totm-on-the-hours
├── playlist/
│ ├── episodes/ # downloaded TOTM episodes (gitignored by default)
│ └── playlist.m3u # auto-generated playlist
├── scripts/
│ ├── fetch_episodes.sh # yt-dlp downloader
│ ├── build_playlist.sh # builds playlist.m3u
│ └── start_stream.sh # ffmpeg loop streamer
├── mediastream/
│ └── mediamtx.yml # MediaMTX config
├── systemd/
│ └── totm-stream.service # 24/7 FFmpeg service
├── .github/workflows/
│ └── channel.yml # GitHub Actions automation
└── docs/
└── index.html # GitHub Pages viewer (hls.js)


---

## 3. Prerequisites

Install these on the machine that will actually run the stream (your own
box, or a self-hosted GitHub Actions runner — **not** a GitHub-hosted
runner, since streaming is a long-running process):

- [MediaMTX](https://github.com/bluenviron/mediamtx) (formerly rtsp-simple-server)
- [FFmpeg](https://ffmpeg.org/) (with `libx264` and `aac` support)
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) (`pip install -U yt-dlp`)
- Python 3.9+ (for yt-dlp) and `bash`

---

## 4. Local setup, step by step

### 4.1 Clone and prepare

```bash
git clone https://github.com/YOUR_GITHUB_USERNAME/totm-on-the-hours.git
cd totm-on-the-hours
chmod +x scripts/*.sh
```

### 4.2 Fetch episodes

```bash
./scripts/fetch_episodes.sh
```

This downloads every video from `@YellowWorldTOTMU` into
`playlist/episodes/`, tracking what's already been fetched in
`playlist/episodes/.download-archive.txt` so re-running the script never
re-downloads existing episodes.

### 4.3 Build the playlist

```bash
./scripts/build_playlist.sh
```

This scans `playlist/episodes/` and writes `playlist/playlist.m3u` in
FFmpeg concat-demuxer format:

file 'episodes/some_episode_title.mp4'
file 'episodes/another_episode.mp4'


Re-run this any time episodes change — it's idempotent and safe.

### 4.4 Run MediaMTX

Download the MediaMTX binary for your platform, then run it with the
provided config:

```bash
./mediamtx mediastream/mediamtx.yml
```

MediaMTX will now be listening for:

- **RTMP ingest** at `rtmp://localhost:1935/live/totm`
- **HLS output** at `http://localhost:8888/live/totm/index.m3u8`

### 4.5 Start the FFmpeg streamer

In a separate terminal (with MediaMTX still running):

```bash
./scripts/start_stream.sh
```

This loops `playlist/playlist.m3u` forever with `-stream_loop -1` and
publishes it into MediaMTX over RTMP. Leave it running — this is your
"channel" playing continuously.

### 4.6 Watch it

Open `docs/index.html` directly in a browser (or serve it with any static
file server), or visit your deployed GitHub Pages URL. It auto-connects to
`http://localhost:8888/live/totm/index.m3u8`, auto-plays (muted, per
browser autoplay policy), and auto-reconnects if the stream drops.

> **Note:** Because the HLS output is bound to `localhost`, the GitHub
> Pages–hosted viewer can only reach your stream when opened on the *same
> machine* that's running MediaMTX (or via a browser on your LAN if you
> widen `hlsAllowOrigin`/bind address in `mediamtx.yml`). This project is
> designed as a local/self-hosted channel — GitHub Pages hosts the player
> UI, not the video itself.

---

## 5. Running 24/7 with systemd

To keep the FFmpeg streamer alive across reboots and crashes:

1. Copy the repo to a stable path, e.g. `/opt/totm-on-the-hours`.
2. Edit `systemd/totm-stream.service` and set `User`, `Group`, and
   `WorkingDirectory`/`ExecStart` to match your install path.
3. Install and enable it:

```bash
sudo cp systemd/totm-stream.service /etc/systemd/system/totm-stream.service
sudo systemctl daemon-reload
sudo systemctl enable --now totm-stream.service
```

4. Check status/logs:

```bash
sudo systemctl status totm-stream.service
journalctl -u totm-stream -f
```

You'll typically also want a matching `mediamtx.service` unit (not
included here — MediaMTX ships its own systemd examples) so MediaMTX
itself starts before `totm-stream.service`, which already declares
`After=` / `Requires=` on `mediamtx.service`.

---

## 6. Self-hosted GitHub Actions runner

The GitHub-hosted runners in `.github/workflows/channel.yml` handle
fetching episodes, building the playlist, and deploying the viewer — but
they **cannot** run a 24/7 streaming process (jobs are time-limited and
ephemeral). For continuous streaming triggered by CI, register a
self-hosted runner on the machine where MediaMTX/FFmpeg actually run:

1. In your repo: **Settings → Actions → Runners → New self-hosted runner**.
2. Follow GitHub's generated `config.sh`/`config.cmd` instructions on your
   streaming host.
3. Give the runner the label **`totm-streamer`** during setup (or add it
   afterward) — the workflow's `stream` job specifically targets
   `runs-on: [self-hosted, totm-streamer]`.
4. Make sure that host already has `totm-stream.service` installed (see
   §5) — the workflow simply runs `sudo systemctl restart
   totm-stream.service` after episodes/playlist update, so the channel
   picks up new content without manual intervention.
5. Ensure the runner's service user has passwordless `sudo` rights for
   `systemctl restart totm-stream.service`, or adjust the workflow step to
   match your permission model.

---

## 7. How GitHub Actions updates episodes

`.github/workflows/channel.yml` runs:

- **On every push to `main`**
- **On a schedule, every 6 hours** (`cron: "0 */6 * * *"`)
- **On manual dispatch**

Job flow:

1. **`update-channel`** (GitHub-hosted): checks out the repo, installs
   yt-dlp/ffmpeg, runs `scripts/fetch_episodes.sh` then
   `scripts/build_playlist.sh`, and commits any resulting changes to
   `playlist/` back to `main`.
2. **`deploy-viewer`** (GitHub-hosted): publishes `docs/` to GitHub Pages
   via the official Pages actions.
3. **`stream`** (self-hosted, only if episodes/playlist changed): restarts
   `totm-stream.service` on your streaming host so the running channel
   picks up the refreshed playlist.

---

## 8. How the GitHub Pages viewer works

`docs/index.html` is a static, dependency-light page that:

- Loads `hls.js` from a CDN and attaches it to a `<video>` element.
- Points at `http://localhost:8888/live/totm/index.m3u8`.
- Auto-plays (muted, to satisfy browser autoplay policies) once the HLS
  manifest is parsed.
- Listens for fatal `hls.js` errors and `<video>` `stalled`/`error`
  events, and automatically retries the connection after a short delay —
  showing a "Stream interrupted — reconnecting…" banner while it does.
- Displays a dark-mode UI with a **FAST Channel** badge and a looping
  **"Now Playing: Talk of the Mock"** ticker banner.

Deploying it is handled by the `deploy-viewer` job above — GitHub Pages
just serves this static file; the actual video bytes come from your local
MediaMTX instance.

---

## 9. Branding reference

- **Channel name:** TOTM: On the Hours
- **Style:** clean, modern, dark-mode
- **Label:** "FAST Channel" badge in the header
- **Banner:** looping "Now Playing: Talk of the Mock" ticker over the player

---

## 10. Troubleshooting

| Symptom | Likely cause |
|---|---|
| Viewer shows "Reconnecting…" indefinitely | MediaMTX or FFmpeg isn't running, or `hlsAllowOrigin` blocks your origin |
| `fetch_episodes.sh` finds nothing new | Archive file already has everything — check `playlist/episodes/.download-archive.txt` |
| `build_playlist.sh` warns "no episode files found" | Run `fetch_episodes.sh` first |
| RTMP publish rejected | Check `publishIPs` in `mediamtx.yml` — it's localhost-only by default |
| Stream stutters | Lower `-b:v` in `scripts/start_stream.sh` or check host CPU headroom for `libx264` |

---

## License

Available for the public domain to remix, copy or redistribute under Creative Commons (CC0).
(C) 2021-2026 YellowWorld under ZeffixOW Group.
