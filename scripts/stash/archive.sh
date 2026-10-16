#!/usr/bin/env bash
# Stash tray archives (services/Stash.qml pack / unpack).
#
#   archive.sh pack <out.zip> <file>...   files of ONE directory → zip next to
#                                         them (name made unique: "x 2.zip")
#   archive.sh unpack <archive> <destdir> extract into destdir: an archive
#                                         with ONE top entry lands as that
#                                         entry, several go into "<stem>/";
#                                         a bare .gz/.xz/.bz2/.zst file is
#                                         just decompressed
# Prints the created path on success. bsdtar reads zip / tar.* / 7z / rar /
# iso / cpio; 7z is the fallback. Temp dirs ".unpack.*" are hidden from the
# tray scanner.
set -uo pipefail

uniq_path() {
    local p=$1 dir base stem ext n=2
    [ -e "$p" ] || { printf '%s\n' "$p"; return; }
    dir=$(dirname -- "$p"); base=$(basename -- "$p")
    if [[ $base == ?*.* && ! -d $p ]]; then stem=${base%.*}; ext=.${base##*.}; else stem=$base; ext=; fi
    while [ -e "$dir/$stem $n$ext" ]; do n=$((n + 1)); done
    printf '%s\n' "$dir/$stem $n$ext"
}

# "a.tar.gz" → "a", "a.zip" → "a"
stem_of() {
    local b
    b=$(basename -- "$1")
    b=$(sed -E 's/\.(tar\.(gz|bz2|xz|zst|lz4|lzma)|tgz|tbz2?|txz|tzst|zip|7z|rar|tar|iso|cpio|gz|bz2|xz|zst)$//I' <<<"$b")
    printf '%s\n' "${b:-archive}"
}

case ${1:-} in
pack)
    out=$(uniq_path "$2"); shift 2
    [ $# -gt 0 ] || exit 2
    cd -- "$(dirname -- "$1")" || exit 1
    names=()
    for f in "$@"; do names+=("./$(basename -- "$f")"); done
    # -y: symlinks stay links (dropMode symlink would zip the originals' trees otherwise).
    zip -q -r -y "$out" "${names[@]}" || { rm -f "$out"; exit 1; }
    printf '%s\n' "$out"
    ;;
unpack)
    src=$2 dest=$3
    lower=${src,,}
    if [[ ! $lower =~ \.tar\.[a-z0-9]+$ && $lower =~ \.(gz|bz2|xz|zst)$ ]]; then
        case ${BASH_REMATCH[1]} in
        gz) dec=(gzip -dc) ;; bz2) dec=(bzip2 -dc) ;; xz) dec=(xz -dc) ;; zst) dec=(zstd -dcq) ;;
        esac
        out=$(uniq_path "$dest/$(basename -- "${src%.*}")")
        "${dec[@]}" -- "$src" >"$out" || { rm -f "$out"; exit 1; }
        printf '%s\n' "$out"
        exit 0
    fi
    tmp=$(mktemp -d -p "$dest" .unpack.XXXXXX) || exit 1
    if ! bsdtar -xf "$src" -C "$tmp" 2>/dev/null; then
        rm -rf "$tmp"; tmp=$(mktemp -d -p "$dest" .unpack.XXXXXX) || exit 1
        command -v 7z >/dev/null && 7z x -y -bd -o"$tmp" -- "$src" >/dev/null 2>&1 || { rm -rf "$tmp"; exit 1; }
    fi
    shopt -s nullglob dotglob
    entries=("$tmp"/*)
    if [ ${#entries[@]} -eq 1 ]; then
        out=$(uniq_path "$dest/$(basename -- "${entries[0]}")")
        mv -- "${entries[0]}" "$out" && rmdir -- "$tmp"
    else
        out=$(uniq_path "$dest/$(stem_of "$src")")
        mv -- "$tmp" "$out"
    fi
    printf '%s\n' "$out"
    ;;
*)
    echo "usage: archive.sh pack <out.zip> <file>... | unpack <archive> <destdir>" >&2
    exit 2
    ;;
esac
