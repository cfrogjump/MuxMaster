#!/usr/bin/env bash
# =============================================================================
# CRF→CQ Calibration Harness
# - Encodes clips with software CRF + hardware CQ/global_quality/bitrate
# - Computes VMAF + SSIM against source
# - Produces mapping tables and summary
# =============================================================================
set -euo pipefail

ENCODER="hevc_videotoolbox"
CODEC="hevc"
CRF_RANGE="16-26:2"
HW_RANGE="14-30:2"
OUT_DIR=""
SW_PRESET="slow"
HW_PRESET=""
CLIPS=()

usage(){
  cat <<'EOF'
Usage: quality_calibrate.sh [options]

Options:
  --encoder NAME       Hardware encoder (hevc_nvenc, hevc_qsv, hevc_videotoolbox, etc.)
  --codec NAME         hevc or h264 (default: hevc)
  --clips PATH         Input clip (repeatable)
  --crf RANGE          CRF range (start-end:step) (default: 16-26:2)
  --hw RANGE           Hardware quality range (default: 14-30:2)
  --out DIR            Output directory (default: artifacts/quality/YYYYMMDD-HHMMSS)
  --sw-preset NAME     Software preset (default: slow)
  --hw-preset NAME     Hardware preset (optional; passed if supported)
  -h, --help           Show help

Notes:
  - NVENC uses -cq, QSV uses -global_quality, VideoToolbox uses -b:v (kbps).
  - For VideoToolbox, pass --hw as bitrate values (kbps) e.g., 2000-12000:1000
EOF
}

require_bin(){
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing dependency: $1" >&2
    exit 1
  }
}

expand_range(){
  local range="$1"
  local start end step
  start="${range%%-*}"
  end="${range#*-}"
  end="${end%%:*}"
  step="${range#*:}"
  step="${step:-1}"
  if [[ -z "$start" || -z "$end" || -z "$step" ]]; then
    echo "Invalid range: $range" >&2
    exit 1
  fi
  local v
  for (( v=start; v<=end; v+=step )); do
    echo "$v"
  done
}

file_bitrate_kbps(){
  local file="$1"
  local br
  br="$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate \
    -of default=nk=1:nw=1 "$file" 2>/dev/null | head -n1)"
  if [[ -n "$br" && "$br" != "N/A" && "$br" != "0" ]]; then
    echo $(( br / 1000 ))
    return 0
  fi
  local dur fsz
  dur="$(ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$file" 2>/dev/null | head -n1)"
  dur="${dur%.*}"
  fsz="$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo 0)"
  if [[ -n "$dur" && "$dur" != "0" ]] && (( dur > 0 )) && (( fsz > 0 )); then
    echo $(( fsz * 8 / dur / 1000 ))
  else
    echo ""
  fi
}

compute_vmaf_ssim(){
  local src="$1" enc="$2" vmaf_log="$3" ssim_log="$4"
  ffmpeg -v error -i "$src" -i "$enc" \
    -filter_complex "[0:v][1:v]libvmaf=log_fmt=json:log_path=${vmaf_log};[0:v][1:v]ssim=stats_file=${ssim_log}" \
    -f null - >/dev/null
}

encoder_quality_flag(){
  case "$ENCODER" in
    *_nvenc) echo "-cq" ;;
    *_qsv) echo "-global_quality" ;;
    *_videotoolbox) echo "-b:v" ;;
    *) echo "" ;;
  esac
}

encoder_pix_fmt(){
  if [[ "$CODEC" == "hevc" ]]; then
    echo "yuv420p10le"
  else
    echo "yuv420p"
  fi
}

encode_sw(){
  local src="$1" out="$2" crf="$3" pix_fmt
  pix_fmt="$(encoder_pix_fmt)"
  if [[ "$CODEC" == "hevc" ]]; then
    ffmpeg -v error -y -i "$src" -map 0:v:0 -an -sn -dn \
      -c:v libx265 -preset "$SW_PRESET" -crf "$crf" -pix_fmt "$pix_fmt" "$out"
  else
    ffmpeg -v error -y -i "$src" -map 0:v:0 -an -sn -dn \
      -c:v libx264 -preset "$SW_PRESET" -crf "$crf" -pix_fmt "$pix_fmt" "$out"
  fi
}

encode_hw(){
  local src="$1" out="$2" qval="$3" pix_fmt qflag
  pix_fmt="$(encoder_pix_fmt)"
  qflag="$(encoder_quality_flag)"
  if [[ -z "$qflag" ]]; then
    echo "Unsupported encoder: $ENCODER" >&2
    exit 1
  fi
  if [[ "$qflag" == "-b:v" ]]; then
    ffmpeg -v error -y -i "$src" -map 0:v:0 -an -sn -dn \
      -c:v "$ENCODER" -b:v "${qval}k" -pix_fmt "$pix_fmt" -allow_sw 1 "$out"
  else
    local -a preset_args=()
    [[ -n "$HW_PRESET" ]] && preset_args=(-preset "$HW_PRESET")
    ffmpeg -v error -y -i "$src" -map 0:v:0 -an -sn -dn \
      -c:v "$ENCODER" "${preset_args[@]}" "$qflag" "$qval" -pix_fmt "$pix_fmt" "$out"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --encoder) ENCODER="$2"; shift 2 ;;
    --codec) CODEC="$2"; shift 2 ;;
    --clips) CLIPS+=("$2"); shift 2 ;;
    --crf) CRF_RANGE="$2"; shift 2 ;;
    --hw) HW_RANGE="$2"; shift 2 ;;
    --out) OUT_DIR="$2"; shift 2 ;;
    --sw-preset) SW_PRESET="$2"; shift 2 ;;
    --hw-preset) HW_PRESET="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
 done

require_bin ffmpeg
require_bin ffprobe
require_bin jq
require_bin bc

if [[ ${#CLIPS[@]} -eq 0 ]]; then
  echo "No clips provided. Use --clips <path> (repeatable)." >&2
  exit 1
fi

if [[ -z "$OUT_DIR" ]]; then
  OUT_DIR="artifacts/quality/$(date +%Y%m%d-%H%M%S)"
fi

mkdir -p "$OUT_DIR"

RESULTS_CSV="$OUT_DIR/results.csv"
MAP_CSV="$OUT_DIR/mapping.csv"
SUMMARY_CSV="$OUT_DIR/mapping_summary.csv"
SUMMARY_MD="$OUT_DIR/mapping.md"

printf "clip,mode,quality,bitrate_kbps,vmaf,ssim\n" > "$RESULTS_CSV"
printf "clip,crf,hw_quality,sw_vmaf,hw_vmaf,delta\n" > "$MAP_CSV"

crf_vals=( $(expand_range "$CRF_RANGE") )
hw_vals=( $(expand_range "$HW_RANGE") )

for clip in "${CLIPS[@]}"; do
  if [[ ! -f "$clip" ]]; then
    echo "Clip not found: $clip" >&2
    exit 1
  fi

  base="$(basename "$clip")"
  base="${base%.*}"

  declare -A sw_vmaf hw_vmaf

  for crf in "${crf_vals[@]}"; do
    out="$OUT_DIR/${base}_sw_crf${crf}.mkv"
    vmaf_log="$OUT_DIR/${base}_sw_crf${crf}_vmaf.json"
    ssim_log="$OUT_DIR/${base}_sw_crf${crf}_ssim.log"

    encode_sw "$clip" "$out" "$crf"
    compute_vmaf_ssim "$clip" "$out" "$vmaf_log" "$ssim_log"

    vmaf="$(jq -r '.pooled_metrics.vmaf.mean // empty' "$vmaf_log" 2>/dev/null)"
    ssim="$(grep -Eo 'All:[0-9.]+' "$ssim_log" | tail -n1 | cut -d: -f2)"
    br="$(file_bitrate_kbps "$out")"

    sw_vmaf["$crf"]="$vmaf"
    printf "%s,sw,%s,%s,%s,%s\n" "$base" "$crf" "${br:-}" "${vmaf:-}" "${ssim:-}" >> "$RESULTS_CSV"
  done

  for q in "${hw_vals[@]}"; do
    out="$OUT_DIR/${base}_hw_q${q}.mkv"
    vmaf_log="$OUT_DIR/${base}_hw_q${q}_vmaf.json"
    ssim_log="$OUT_DIR/${base}_hw_q${q}_ssim.log"

    encode_hw "$clip" "$out" "$q"
    compute_vmaf_ssim "$clip" "$out" "$vmaf_log" "$ssim_log"

    vmaf="$(jq -r '.pooled_metrics.vmaf.mean // empty' "$vmaf_log" 2>/dev/null)"
    ssim="$(grep -Eo 'All:[0-9.]+' "$ssim_log" | tail -n1 | cut -d: -f2)"
    br="$(file_bitrate_kbps "$out")"

    hw_vmaf["$q"]="$vmaf"
    printf "%s,hw,%s,%s,%s,%s\n" "$base" "$q" "${br:-}" "${vmaf:-}" "${ssim:-}" >> "$RESULTS_CSV"
  done

  for crf in "${crf_vals[@]}"; do
    sw="${sw_vmaf[$crf]:-}"
    [[ -z "$sw" ]] && continue

    local_best_q=""
    local_best_vmaf=""
    local_best_delta=""

    for q in "${hw_vals[@]}"; do
      hw="${hw_vmaf[$q]:-}"
      [[ -z "$hw" ]] && continue
      delta="$(echo "scale=4; ($sw - $hw)" | bc 2>/dev/null)"
      abs="${delta#-}"
      if [[ -z "$local_best_delta" ]] || (( $(echo "$abs < $local_best_delta" | bc -l 2>/dev/null) )); then
        local_best_delta="$abs"
        local_best_q="$q"
        local_best_vmaf="$hw"
      fi
    done

    if [[ -n "$local_best_q" ]]; then
      printf "%s,%s,%s,%s,%s,%s\n" "$base" "$crf" "$local_best_q" "$sw" "$local_best_vmaf" "$local_best_delta" >> "$MAP_CSV"
    fi
  done

  unset sw_vmaf hw_vmaf
 done

# Summary: average HW quality per CRF across clips
awk -F',' 'NR>1 {sum[$2]+=$3; cnt[$2]+=1} END {print "crf,avg_hw_quality"; for (c in sum) printf "%s,%.2f\n", c, sum[c]/cnt[c]}' "$MAP_CSV" \
  | sort -t',' -k1,1n > "$SUMMARY_CSV"

cat <<EOF > "$SUMMARY_MD"
# CRF→HW Quality Mapping Summary

Encoder: $ENCODER
Codec: $CODEC
CRF Range: $CRF_RANGE
HW Range: $HW_RANGE

## Average Mapping (across clips)


table
EOF

{
  echo "| CRF | Avg HW Quality |"
  echo "| --- | --- |"
  tail -n +2 "$SUMMARY_CSV" | while IFS=',' read -r crf avg; do
    echo "| $crf | $avg |"
  done
} >> "$SUMMARY_MD"

echo "Results written to: $OUT_DIR"
