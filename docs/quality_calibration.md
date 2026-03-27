---
description: CRF → hardware quality calibration harness
---

# CRF → Hardware Quality Calibration

This harness builds a **CRF → hardware quality mapping** by comparing software CRF encodes
against hardware CQ/global_quality/bitrate encodes using **VMAF + SSIM**.

## Requirements

- `ffmpeg` with `libvmaf` and `ssim` filters
- `ffprobe`
- `jq`, `bc`

> Tip: `ffmpeg -filters | grep vmaf` should return `libvmaf`.

## Script Location

`tools/quality_calibrate.sh`

## Inputs

- **Clips**: Provide multiple representative sources (4K HDR, 4K SDR, 1080p film, animation, noisy 720p).
- **Encoder**: `hevc_nvenc`, `hevc_qsv`, or `hevc_videotoolbox` (and H.264 variants).
- **Ranges**:
  - CRF sweep: `16-26:2` (default)
  - HW quality sweep: `14-30:2` (default)
  - VideoToolbox: **use bitrate kbps range** in `--hw` (e.g., `2000-12000:1000`).

## Example Runs

### VideoToolbox (HEVC)
```bash
tools/quality_calibrate.sh \
  --encoder hevc_videotoolbox \
  --codec hevc \
  --clips assets/quality/clip1.mkv --clips assets/quality/clip2.mkv \
  --crf 16-26:2 \
  --hw 2000-12000:1000
```

### NVENC (HEVC)
```bash
tools/quality_calibrate.sh \
  --encoder hevc_nvenc \
  --codec hevc \
  --clips assets/quality/clip1.mkv --clips assets/quality/clip2.mkv \
  --crf 16-26:2 \
  --hw 14-30:2
```

## Outputs

All artifacts are written to `artifacts/quality/YYYYMMDD-HHMMSS/`:

- `results.csv` — raw per‑encode metrics (bitrate, VMAF, SSIM)
- `mapping.csv` — per‑clip CRF → HW quality match (closest VMAF)
- `mapping_summary.csv` — average HW quality per CRF
- `mapping.md` — readable summary table
- `*_vmaf.json`, `*_ssim.log` — raw metric logs

## Notes

- This is **offline calibration**. Outputs can be used to build a static mapping table
  per encoder + resolution tier.
- HW encoders are selected by `--encoder` and must be supported by your ffmpeg build.
- If VMAF isn’t available, install an ffmpeg build with `libvmaf`.
