#!/usr/bin/env bash
set -euo pipefail

URL="$1"
SPLIT_SIZE="${2:-50}"

if [[ -z "${URL}" ]]; then
  echo "Usage: $0 <narou_url> [split_size]"
  exit 1
fi

# メタデータ取得
META=$(fanficfare \
  --non-interactive \
  --meta-only \
  --json-meta \
  "$URL")

TITLE=$(echo $META | jq -r '.title' | python3 -c "import html, sys; print(html.unescape(sys.stdin.read().strip()))")
AUTHOR=$(echo $META | jq -r '.author')
NCODE=$(echo $META | jq -r '.storyId')
TOTAL_CHAPTERS=$(echo $META | jq -r '.numChapters')

# 出力フォルダ準備
OUTPUT_FOLDER="output_${NCODE}"
rm -rf "$OUTPUT_FOLDER"
mkdir "$OUTPUT_FOLDER"

if [[ ! "$TOTAL_CHAPTERS" =~ ^[0-9]+$ ]]; then
  echo "TOTAL_CHAPTERS is not a number: $TOTAL_CHAPTERS" >&2
  exit 1
fi

if [[ -z "$TOTAL_CHAPTERS" || "$TOTAL_CHAPTERS" == "null" ]]; then
  echo "Failed to get chapter count"
  exit 1
fi

echo "Total chapters: $TOTAL_CHAPTERS"

START=1
VOL=1

while (( START <= TOTAL_CHAPTERS )); do
  END=$(( START + SPLIT_SIZE - 1 ))
  if (( END > TOTAL_CHAPTERS )); then
    END="$TOTAL_CHAPTERS"
  fi

  RANGE_URL="${URL}[${START}-${END}]"
  OUT_FILE="${NCODE}_vol${VOL}_${START}-${END}"

  echo "Generating volume $VOL: $START-$END"

  fanficfare \
    --non-interactive \
    -o output_filename="${OUT_FILE}.epub" \
    "$RANGE_URL"

  # 解凍
  tmp="tmp_${NCODE}_${VOL}"

  rm -rf "$tmp"
  mkdir "$tmp"

  unzip -q "${OUT_FILE}.epub" -d "$tmp"

  # OPF 修正
  OPF_FILE=$(find "$tmp" -name "*.opf" | head -n 1)

  if [[ -z "$OPF_FILE" || "$OPF_FILE" == "null" ]]; then
    echo "Failed to get opt file"
    exit 1
  fi

  sed -i \
  's/<spine/<spine page-progression-direction="rtl"/' \
  "$OPF_FILE"
  sed -i \
  's/<\/metadata/<meta name="primary-writing-mode" content="horizontal-rl" \/><\/metadata/' \
  "$OPF_FILE"

  # 再圧縮
  OUTPUT_TITLE="【${VOL}】${TITLE}"

  cd "$tmp"

  # mimetype を最初に、無圧縮
  zip -qX0 "../$OUTPUT_FOLDER/$OUTPUT_TITLE.epub" mimetype

  # 残りを圧縮して追加
  zip -qXr9D "../$OUTPUT_FOLDER/$OUTPUT_TITLE.epub" . -x mimetype

  cd ../

  START=$(( END + 1 ))
  VOL=$(( VOL + 1 ))
done

# クリーニング
rm -rf tmp_*/ *.epub
