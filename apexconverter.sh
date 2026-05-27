#!/bin/bash

# =========================================================

# Android APEX -> EXT4 + AVB Repacker

# FINAL Optimized Ubuntu PC Version

# By RofikKernelDev

# =========================================================

set +e

IN="$1"
OUT="$2"

WORK="./apex_work"

AVBTOOL="${AVBTOOL:-avbtool}"

# =========================================================

# CHECK ARGUMENTS

# =========================================================

if [ -z "$IN" ] || [ -z "$OUT" ]; then
echo ""
echo "Usage:"
echo "sudo apexconvert <input_apex_folder> <output_folder>"
echo ""
echo "Example:"
echo "sudo apexconvert ./system/system/apex ./out"
echo ""
exit 1
fi

# =========================================================

# CHECK DEPENDENCIES

# =========================================================

REQS=(
7z
fsck.erofs
mke2fs
mount
umount
zip
unzip
file
python3
du
awk
)

for BIN in "${REQS[@]}"; do
if ! command -v "$BIN" >/dev/null 2>&1; then
echo "[-] Missing dependency: $BIN"
exit 1
fi
done

# =========================================================

# CHECK AVBTOOL

# =========================================================

if ! command -v "$AVBTOOL" >/dev/null 2>&1; then


if [ -f "./avbtool.py" ]; then
    AVBTOOL="python3 ./avbtool.py"
elif [ -f "$HOME/avb/avbtool.py" ]; then
    AVBTOOL="python3 $HOME/avb/avbtool.py"
else
    echo "[-] avbtool not found"
    echo ""
    echo "Clone from:"
    echo "git clone https://android.googlesource.com/platform/external/avb ~/avb"
    echo ""
    exit 1
fi


fi

# =========================================================

# CLEANUP HANDLER

# =========================================================

cleanup_mounts() {


find "$WORK" -type d -name mnt 2>/dev/null | while read m; do
    sudo umount -lf "$m" 2>/dev/null
done


}

trap cleanup_mounts EXIT

# =========================================================

# PREPARE

# =========================================================

mkdir -p "$OUT"

rm -rf "$WORK"
mkdir -p "$WORK"

echo "[*] Starting batch APEX -> EXT4 + AVB conversion"

# =========================================================

# LOOP ALL APEX

# =========================================================

for apex in "$IN"/*.apex; do


[ -f "$apex" ] || continue

NAME=$(basename "$apex" .apex)

echo ""
echo "[*] Processing: $NAME"

CUR="$WORK/$NAME"

rm -rf "$CUR"
mkdir -p "$CUR"

# =====================================================
# Extract original apex
# =====================================================

7z x "$apex" -o"$CUR" > /dev/null

PAYLOAD="$CUR/apex_payload.img"

if [ ! -f "$PAYLOAD" ]; then
    echo "[-] apex_payload.img missing"
    continue
fi

TYPE=$(file "$PAYLOAD")

mkdir -p "$CUR/fs"

# =====================================================
# Handle EROFS
# =====================================================

if echo "$TYPE" | grep -qi erofs; then

    echo "    EROFS detected -> converting to EXT4"

    fsck.erofs --extract="$CUR/fs" "$PAYLOAD"

# =====================================================
# Handle EXT filesystem
# =====================================================

elif echo "$TYPE" | grep -Eqi 'ext2|ext3|ext4'; then

    echo "    EXT filesystem detected"

    mkdir -p "$CUR/mnt"

    sudo mount -o loop,ro -t ext4 "$PAYLOAD" "$CUR/mnt"

    cp -a "$CUR/mnt"/. "$CUR/fs"/

    sudo umount "$CUR/mnt"

else

    echo "[-] Unsupported filesystem"
    echo "    $TYPE"

    continue

fi

# =====================================================
# Remove old payload
# =====================================================

rm -f "$CUR/apex_payload.img"

# =====================================================
# Calculate dynamic filesystem size
# =====================================================

echo "    Calculating filesystem size"

FS_SIZE=$(du -sb "$CUR/fs" | awk '{print $1}')

# add 64MB safety padding
IMG_SIZE=$((FS_SIZE + 64 * 1024 * 1024))

# align to 4K
IMG_SIZE=$(( (IMG_SIZE + 4095) / 4096 * 4096 ))

echo "    Image size: $IMG_SIZE bytes"

# =====================================================
# Build EXT4 payload
# =====================================================

echo "    Building EXT4 payload"

mke2fs \
    -t ext4 \
    -O ^has_journal,^metadata_csum,^64bit,^orphan_file \
    -m 0 \
    -d "$CUR/fs" \
    "$CUR/apex_payload.img" \
    "$IMG_SIZE" > /dev/null 2>&1

# =====================================================
# Verify filesystem
# =====================================================

echo "    Verifying filesystem"

file "$CUR/apex_payload.img"

# =====================================================
# Calculate AVB partition size
# =====================================================

PART_SIZE=$((IMG_SIZE + 16 * 1024 * 1024))

# align to 4K
PART_SIZE=$(( (PART_SIZE + 4095) / 4096 * 4096 ))

echo "    Partition size: $PART_SIZE bytes"

# =====================================================
# Add AVB footer
# =====================================================

echo "    Adding AVB footer"

$AVBTOOL add_hashtree_footer \
    --image "$CUR/apex_payload.img" \
    --partition_name apex_payload \
    --partition_size "$PART_SIZE" \
    --hash_algorithm sha256 \
    --do_not_generate_fec

if [ $? -ne 0 ]; then
    echo "[-] Failed to add AVB footer"
    continue
fi

# =====================================================
# Cleanup temp dirs
# =====================================================

rm -rf "$CUR/fs"
rm -rf "$CUR/mnt"

# =====================================================
# Remove old output
# =====================================================

rm -f "$OUT/$NAME.apex"

# =====================================================
# Repack APEX
# =====================================================

echo "    Repacking APEX"

(
    cd "$CUR"

    7z a \
        -tzip \
        -mx=0 \
        "$OLDPWD/$OUT/$NAME.apex" \
        ./* > /dev/null
)

echo "    DONE"


done

# =========================================================

# CREATE FINAL ZIP PACKAGE

# =========================================================

FINAL_ZIP="converted_apex_ext4_avb.zip"

echo ""
echo "[*] Creating final ZIP package"

cd "$OUT"

zip -r "../$FINAL_ZIP" ./*.apex > /dev/null

cd "$OLDPWD"

# =========================================================

# CLEANUP

# =========================================================

rm -rf "$WORK"

echo ""
echo "[*] ALL DONE"
echo "[*] Final converted APEX files:"
echo "    $OUT"
echo ""
echo "[*] Final ZIP package:"
echo "    $FINAL_ZIP"
echo ""
