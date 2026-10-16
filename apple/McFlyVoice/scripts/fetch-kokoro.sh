#!/bin/bash
# Downloads the Kokoro-82M voice (Core ML conversion, Apache-2.0) that McFly bundles, the
# same files as Homestead's, about 200 MB, into Sources/McFlyVoice/Kokoro. Run once per
# checkout, before building:
#
#   apple/McFlyVoice/scripts/fetch-kokoro.sh [--from <a Kokoro folder already fetched>]
#
# --from copies files from another copy (Homestead's, or the release script's own checkout)
# instead of downloading them; every file is still checked against its pinned hash.
#
# Files come from huggingface.co/mattmireles/kokoro-coreml at the revision pinned below and
# are checked against the hashes in scripts/kokoro-files.txt. The app never downloads
# anything: these files ship inside it.
set -euo pipefail
cd "$(dirname "$0")/.."

REVISION="9183566f294ca3f31a63fd2767cf5848bfebfd50"
BASE="https://huggingface.co/mattmireles/kokoro-coreml/resolve/$REVISION"
DEST="Sources/McFlyVoice/Kokoro"
FROM=""
[[ "${1:-}" == "--from" && -n "${2:-}" ]] && FROM="$2"

verify() {
    local kind="$1" hash="$2" file="$3"
    if [[ "$kind" == "sha256" ]]; then
        [[ "$(shasum -a 256 "$file" | cut -d' ' -f1)" == "$hash" ]]
    else
        [[ "$(git hash-object "$file")" == "$hash" ]]
    fi
}

fetched=0
while read -r kind hash bytes path; do
    [[ -z "$kind" || "$kind" == \#* ]] && continue
    file="$DEST/$path"
    if [[ -f "$file" ]] && verify "$kind" "$hash" "$file"; then
        continue
    fi
    mkdir -p "$(dirname "$file")"
    if [[ -n "$FROM" && -f "$FROM/$path" ]]; then
        cp "$FROM/$path" "$file.partial"
    else
        echo "▸ $path ($((bytes / 1000)) KB)"
        curl -fsSL --retry 3 -o "$file.partial" "$BASE/$path"
    fi
    if ! verify "$kind" "$hash" "$file.partial"; then
        rm -f "$file.partial"
        echo "error: $path doesn't match its pinned hash" >&2
        exit 1
    fi
    mv "$file.partial" "$file"
    fetched=$((fetched + 1))
done < scripts/kokoro-files.txt

echo "Kokoro voice ready in $DEST ($fetched files fetched, all verified)."
