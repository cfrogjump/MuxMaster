# ![muxm](./assets/muxm_header_small.png) MuxMaster

**MuxMaster** – a versatile, cross-platform video repacking and encoding utility that preserves HDR, Dolby Vision, and high-quality audio while optimizing for Plex and Apple TV Direct Play. Supports smart codec handling, color space matching, error recovery, and optional stereo fallback.

## Table of Contents
- [Features](#features)
- [Format Profiles](#profiles)
- [Installation](#installation)
- [Usage](#usage)
- [Examples](#examples)
- [Configuration](#configuration)
- [Going Forward](#goingforward)
- [License](#license)
- [Contributing](#contributing)
- [Author](#author)


## ✨ Features <a id="features"></a>

- **Format Profiles** – One-flag presets for common workflows: `dv-archival`, `hdr10-hq`, `atv-directplay-hq`, `universal`
- **Preserves HDR & Dolby Vision** – Keeps original color depth and HDR metadata where possible
- **Audio Preservation** – Retains E-AC-3, AC-3, or AAC without re-encoding; converts others to best Direct Play-compatible format
- **Lossless Audio Passthrough** – TrueHD, DTS-HD MA, and FLAC pass through untouched when the profile and container support it
- **Stereo Fallback** – Optionally creates a high-quality stereo track for compatibility
- **Tone-mapping** – Converts HDR/HLG content to SDR (H.264) for universal playback
- **Forced Subtitle Burn-in** – Burns forced subs into the video stream for guaranteed display
- **Skip-if-Ideal** – Detects when source already matches the target profile and skips processing
- **Error Recovery** – Detects, logs, and gracefully handles mid-process failures
- **Conflict Warnings** – Detects contradictory flag + profile combinations and warns (never errors)
- **Color Space Matching** – Matches output color space & depth to the source if not Dolby Vision
- **Cross-Platform** – Works on macOS and most modern Linux distributions
- **Dry-Run Mode** – Test workflows without writing files
- **JSON Reporting** – Generates a machine-readable report of all checks and fixes alongside output
- **Checksum Verification** – Ensures output integrity
- **Clean-up on Failure** – Removes incomplete temp files when an error occurs

---

## 🎯 Format Profiles <a id="profiles"></a>

Profiles are named presets that configure `muxm` for a specific use case in a single flag. Every setting a profile changes can be individually overridden with CLI flags.

```bash
muxm --profile <name> input.mkv
```

| Profile | Goal | Container | Video | Audio | DV |
|---|---|---|---|---|---|
| `dv-archival` | Lossless preservation | MKV | Copy (no re-encode) | Lossless passthrough | Preserve |
| `hdr10-hq` | Max HDR10 quality | MKV | HEVC CRF 17 | Lossless + stereo fallback | Strip |
| `atv-directplay-hq` | Apple TV Direct Play | MP4 | HEVC Main10 (copy if compliant) | E-AC-3 + AAC stereo | P8.1 auto |
| `universal` | Play anywhere | MP4 | H.264 SDR (tone-map HDR) | AAC stereo | Strip |

### `dv-archival` — Dolby Vision Archival

For collectors who want bit-perfect preservation. Copies video without re-encoding, passes lossless audio through, keeps all subtitles and chapters, and generates a JSON report. Skips processing entirely if the source already matches.

```bash
muxm --profile dv-archival movie.mkv
```

### `hdr10-hq` — High Quality HDR10

Strips Dolby Vision layers and re-encodes to clean HDR10 HEVC at CRF 17. Preserves lossless audio (TrueHD, DTS-HD MA, FLAC) and adds a stereo fallback track. MKV output.

```bash
muxm --profile hdr10-hq movie.mkv
```

### `atv-directplay-hq` — Apple TV Direct Play

Targets true Direct Play on Apple TV 4K via Plex: MP4 container, HEVC Main10 with DV Profile 8.1 when possible, E-AC-3 surround with AAC stereo fallback, and forced subtitle burn-in. Copies compliant video without re-encoding. Skips processing if source is already ATV-compliant.

```bash
muxm --profile atv-directplay-hq movie.mkv
```

### `universal` — Universal Compatibility

Plays on everything: old Rokus, mobile devices, web browsers, non-HDR TVs. Tone-maps HDR to SDR, encodes to H.264, forces AAC stereo audio, burns forced subtitles, exports others as external SRT, and strips chapters and non-essential metadata.

```bash
muxm --profile universal movie.mkv
```

### Overriding Profile Defaults

Profiles are starting points — every setting can be overridden with CLI flags:

```bash
# Use hdr10-hq but with a different CRF and no stereo fallback
muxm --profile hdr10-hq --crf 20 --no-stereo-fallback movie.mkv

# Use universal but keep chapters
muxm --profile universal --keep-chapters movie.mkv

# Use atv-directplay-hq but output to MKV (you'll get a warning)
muxm --profile atv-directplay-hq --output-ext mkv movie.mkv
```

---

## 📦 Installation <a id="installation"></a>

```bash
# Clone the repository
git clone https://github.com/theBluWiz/muxmaster.git
cd muxmaster

# Make the script executable
chmod +x muxm

# Optionally move to a location in your PATH
sudo mv muxm /usr/local/bin/muxm
```

### Dependencies

- **ffmpeg** and **ffprobe** (required)
- **dovi_tool** (required for Dolby Vision handling; auto-disabled if missing)
- **sub2srt** or equivalent OCR tool (optional, for PGS subtitle conversion)

---

## 🚀 Usage <a id="usage"></a>

```bash
muxm [options] <source> [target.mp4]
```

### Arguments
- `<source>` – Input media file (e.g., `movie.mkv`)
- `[target]` – Output file (optional; defaults to `<source>.<output-ext>`)

### Key Flags

| Flag | Description |
|---|---|
| `--profile NAME` | Apply a format profile (`dv-archival`, `hdr10-hq`, `atv-directplay-hq`, `universal`) |
| `--dry-run` | Simulate without writing output |
| `--crf N` | Set video CRF value |
| `-p, --preset NAME` | x265 encoder preset (e.g., `slow`, `medium`) |
| `--video-codec libx265\|libx264` | Video encoder |
| `--tonemap` | Tone-map HDR to SDR |
| `--audio-force-codec CODEC` | Force all audio to a specific codec |
| `--audio-lossless-passthrough` | Allow lossless codecs to pass through |
| `--sub-burn-forced` | Burn forced subtitles into video |
| `--output-ext mp4\|mkv\|m4v\|mov` | Output container |
| `--strip-metadata` | Strip non-essential metadata |
| `--skip-if-ideal` | Skip processing if source matches target |
| `--print-effective-config` | Show resolved config after all overrides |

Run `muxm --help` for the full flag reference.

---

## 🔍 Examples <a id="examples"></a>

```bash
# Standard encode with defaults (HEVC CRF 18, stereo fallback, MP4)
muxm input.mkv output.mp4

# Apple TV Direct Play — one flag does it all
muxm --profile atv-directplay-hq input.mkv

# Archival — copy video, keep lossless audio, generate report
muxm --profile dv-archival input.mkv

# Universal compatibility — H.264 SDR, AAC stereo, burn forced subs
muxm --profile universal input.mkv

# HDR10 high quality with custom CRF
muxm --profile hdr10-hq --crf 20 input.mkv

# Check what a profile actually sets before running
muxm --profile atv-directplay-hq --print-effective-config

# Dry run to preview the pipeline
muxm --profile universal --dry-run input.mkv
```

---

## ⚙️ Configuration <a id="configuration"></a>

`muxm` reads configuration from multiple levels, applied in this order (lowest → highest precedence):

```
Hardcoded defaults
  → /etc/.muxmrc          (system-wide)
    → ~/.muxmrc            (user defaults)
      → ./.muxmrc          (project-specific)
        → --profile <name> (format profile)
          → CLI flags      (highest — always wins)
```

### Setting a Default Profile

Add to any `.muxmrc` file:

```bash
# ~/.muxmrc — always use Apple TV Direct Play unless overridden
PROFILE_NAME="atv-directplay-hq"
```

CLI `--profile` always overrides a config-file `PROFILE_NAME`.

### Verifying Effective Configuration

```bash
# See what the resolved config looks like after all sources merge
muxm --profile hdr10-hq --crf 20 --print-effective-config
```

This shows every variable grouped by section, the active profile name, and whether the profile came from a config file or the CLI.

---

## Going Forward <a id="goingforward"></a>
- ~~Format Presets – Introduce named presets for different targets (Apple TV, Plex, archival storage).~~ ✅ Implemented
- ~~Environment Configuration – Support local and global config files.~~ ✅ Implemented
- ~~Checksum Verification – Integrate optional hash verification of outputs.~~ ✅ Implemented
- ~~Logging Enhancements – Support JSON log output.~~ ✅ Implemented (`--report-json`)
- Batch Directory Processing – Add logic to process all compatible files in a directory (including subdirectories) with filtering by extension or codec.
- Parallel Processing Option – Allow multi-threaded encoding when hardware resources are available, with automatic core detection.
- Codec Expansion – Broaden compatibility to include VP9, AV1, and ProRes workflows while preserving current Dolby Vision/HDR handling.
- Interactive Mode – Add a guided CLI wizard for non-technical users to configure a job without needing full command-line knowledge.
- Self-Update Mechanism – Include an update command to pull the latest release from GitHub automatically.
- Custom Naming Templates – Allow users to define output filename patterns with variables (e.g., `{title}_{codec}_{crf}`).

## 📄 License <a id="license"></a>

MuxMaster is freeware for personal, non-commercial use.
Any business, government, or organizational use requires a paid license.

Full license text available in [LICENSE.md](./LICENSE.md)

## 🤝 Contributing <a id="contributing"></a>

Contributions are welcome for bug reports, feature requests, and documentation improvements.
Please note that all code changes must be approved by the maintainer and comply with the license.

## 👤 Author <a id="author"></a>

Maintainer: Jamey Wicklund (theBluWiz)  
Email: [thebluwiz@thoughtspace.place](mailto:thebluwiz@thoughtspace.place)

> **Tip:** If you are a hiring manager or recruiter, this project demonstrates advanced Bash scripting, media processing workflows, error handling, and cross-platform compatibility design.