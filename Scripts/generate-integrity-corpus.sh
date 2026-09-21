#!/bin/zsh
#
# Builds the clean-codestream corpus that calibrates the entropy integrity
# thresholds (see Documentation/INTEGRITY_CALIBRATION.md).
#
# Requires kdu_compress, opj_compress, ojph_compress and grk_compress on PATH.
# Writes source images to src/ and codestreams to clean/, with manifest.tsv
# recording the exact command behind each one.
#
# Build a clean-codestream corpus across four independent encoders.
# The point is the MQ *termination* modes: BYPASS, RESTART, PTERM and
# SEGMARK all change how much of each segment a decoder consumes, which is
# exactly the quantity the integrity check thresholds on.
set -u
cd "$(dirname $0)"
mkdir -p src
# Source images: gradients, texture, sharp edges and pseudo-random noise.
# Noise matters most — it is incompressible, so it produces the largest
# code-blocks and the longest MQ segments.
python3 - src <<'PYEOF'
import sys, os, math, struct
d = sys.argv[1]
def pgm(path, w, h, maxval, fn):
    data = bytearray()
    for y in range(h):
        for x in range(w):
            v = fn(x, y) % (maxval + 1)
            data.extend(struct.pack('>H', v) if maxval > 255 else bytes([v]))
    open(path, 'wb').write(b"P5\n%d %d\n%d\n" % (w, h, maxval) + data)
def ppm(path, w, h, maxval, fn):
    data = bytearray()
    for y in range(h):
        for x in range(w):
            r, g, b = fn(x, y)
            data.extend(struct.pack('>HHH', r % 65536, g % 65536, b % 65536)
                        if maxval > 255 else bytes([r % 256, g % 256, b % 256]))
    open(path, 'wb').write(b"P6\n%d %d\n%d\n" % (w, h, maxval) + data)
grad  = lambda x, y: x * 7 + y * 13
tex   = lambda x, y: int(2048 + 1800 * math.sin(x / 5.0) * math.cos(y / 7.0))
edges = lambda x, y: 65000 if ((x // 16) + (y // 16)) % 2 else 300
noise = lambda x, y: (x * 1103515245 + y * 12345 + 7919) >> 5
pgm(f"{d}/g8_64x48.pgm",     64,  48,   255, grad)
pgm(f"{d}/g16_64x48.pgm",    64,  48, 65535, grad)
pgm(f"{d}/g16_256x256.pgm", 256, 256, 65535, tex)
pgm(f"{d}/g16_512x512.pgm", 512, 512, 65535, tex)
pgm(f"{d}/g16_517x389.pgm", 517, 389, 65535, tex)
pgm(f"{d}/g16_edges.pgm",   256, 256, 65535, edges)
pgm(f"{d}/g16_noise.pgm",   256, 256, 65535, noise)
pgm(f"{d}/g12_256x256.pgm", 256, 256,  4095, tex)
ppm(f"{d}/rgb8_256x256.ppm",256, 256,   255, lambda x, y: (x % 256, y % 256, (x ^ y) % 256))
ppm(f"{d}/rgb16_128x96.ppm",128,  96, 65535, lambda x, y: (x * 211 % 65536, y * 307 % 65536, (x * y) % 65536))
PYEOF

OUT=clean; mkdir -p $OUT; rm -f $OUT/*.j2k $OUT/*.jph 2>/dev/null || true
MANIFEST=manifest.tsv; : > $MANIFEST
n=0; fail=0
emit() { # emit <name> <cmd...>
  local name=$1; shift
  if "$@" >/dev/null 2>&1 && [ -s "$OUT/$name" ]; then
    printf '%s\t%s\t%s\n' "$name" "$(stat -f %z $OUT/$name)" "$*" >> $MANIFEST; n=$((n+1))
  else
    rm -f "$OUT/$name"; fail=$((fail+1))
  fi
}

for s in src/*.pgm src/*.ppm; do
  b=$(basename $s); b=${b%.*}

  # --- Kakadu: the reference implementation, and the widest mode coverage ---
  emit "kdu_${b}_lossless.j2k"      kdu_compress -i $s -o $OUT/kdu_${b}_lossless.j2k Creversible=yes -quiet
  emit "kdu_${b}_lossy.j2k"         kdu_compress -i $s -o $OUT/kdu_${b}_lossy.j2k -rate 1.0 -quiet
  emit "kdu_${b}_L5.j2k"            kdu_compress -i $s -o $OUT/kdu_${b}_L5.j2k Creversible=yes Clayers=5 -quiet
  emit "kdu_${b}_tiled.j2k"         kdu_compress -i $s -o $OUT/kdu_${b}_tiled.j2k Creversible=yes "Stiles={128,128}" -quiet
  emit "kdu_${b}_cblk32.j2k"        kdu_compress -i $s -o $OUT/kdu_${b}_cblk32.j2k Creversible=yes "Cblk={32,32}" -quiet
  emit "kdu_${b}_bypass.j2k"        kdu_compress -i $s -o $OUT/kdu_${b}_bypass.j2k Creversible=yes Cmodes=BYPASS -quiet
  emit "kdu_${b}_restart.j2k"       kdu_compress -i $s -o $OUT/kdu_${b}_restart.j2k Creversible=yes Cmodes=RESTART -quiet
  emit "kdu_${b}_pterm.j2k"         kdu_compress -i $s -o $OUT/kdu_${b}_pterm.j2k Creversible=yes Cmodes=PREDICTABLE -quiet
  emit "kdu_${b}_segmark.j2k"       kdu_compress -i $s -o $OUT/kdu_${b}_segmark.j2k Creversible=yes Cmodes=SEGMARK -quiet
  emit "kdu_${b}_byprest.j2k"       kdu_compress -i $s -o $OUT/kdu_${b}_byprest.j2k Creversible=yes "Cmodes=BYPASS|RESTART" -quiet
  emit "kdu_${b}_allmodes.j2k"      kdu_compress -i $s -o $OUT/kdu_${b}_allmodes.j2k Creversible=yes "Cmodes=BYPASS|RESTART|PREDICTABLE|SEGMARK" -quiet
  emit "kdu_${b}_rpcl.j2k"          kdu_compress -i $s -o $OUT/kdu_${b}_rpcl.j2k Creversible=yes Corder=RPCL -quiet
  emit "kdu_${b}_sop_eph.j2k"       kdu_compress -i $s -o $OUT/kdu_${b}_sop_eph.j2k Creversible=yes Suse_sop=yes Suse_eph=yes -quiet
  emit "kdu_${b}_ht.j2k"            kdu_compress -i $s -o $OUT/kdu_${b}_ht.j2k Creversible=yes Cmodes=HT -quiet

  # --- OpenJPEG ---
  emit "opj_${b}_lossless.j2k"      opj_compress -i $s -o $OUT/opj_${b}_lossless.j2k
  emit "opj_${b}_lossy.j2k"         opj_compress -i $s -o $OUT/opj_${b}_lossy.j2k -r 10
  emit "opj_${b}_L5.j2k"            opj_compress -i $s -o $OUT/opj_${b}_L5.j2k -r 20,10,5,2,1
  emit "opj_${b}_tiled.j2k"         opj_compress -i $s -o $OUT/opj_${b}_tiled.j2k -t 128,128
  emit "opj_${b}_cblk32.j2k"        opj_compress -i $s -o $OUT/opj_${b}_cblk32.j2k -b 32,32
  emit "opj_${b}_bypass.j2k"        opj_compress -i $s -o $OUT/opj_${b}_bypass.j2k -M 1
  emit "opj_${b}_restart.j2k"       opj_compress -i $s -o $OUT/opj_${b}_restart.j2k -M 4
  emit "opj_${b}_segmark.j2k"       opj_compress -i $s -o $OUT/opj_${b}_segmark.j2k -M 32
  emit "opj_${b}_allmodes.j2k"      opj_compress -i $s -o $OUT/opj_${b}_allmodes.j2k -M 37
  emit "opj_${b}_sop_eph.j2k"       opj_compress -i $s -o $OUT/opj_${b}_sop_eph.j2k -SOP -EPH

  # --- OpenJPH (HTJ2K) ---
  emit "ojph_${b}_rev.j2k"          ojph_compress -i $s -o $OUT/ojph_${b}_rev.j2k -reversible true
  emit "ojph_${b}_irrev.j2k"        ojph_compress -i $s -o $OUT/ojph_${b}_irrev.j2k -reversible false
  emit "ojph_${b}_blk32.j2k"        ojph_compress -i $s -o $OUT/ojph_${b}_blk32.j2k -reversible true -block_size "{32,32}"
  emit "ojph_${b}_tiled.j2k"        ojph_compress -i $s -o $OUT/ojph_${b}_tiled.j2k -reversible true -tile_size "{128,128}"

  # --- Grok ---
  emit "grk_${b}_lossless.j2k"      grk_compress -i $s -o $OUT/grk_${b}_lossless.j2k
  emit "grk_${b}_lossy.j2k"         grk_compress -i $s -o $OUT/grk_${b}_lossy.j2k -r 10
  emit "grk_${b}_L5.j2k"            grk_compress -i $s -o $OUT/grk_${b}_L5.j2k -r 20,10,5,2,1
  emit "grk_${b}_tiled.j2k"         grk_compress -i $s -o $OUT/grk_${b}_tiled.j2k -t 128,128
  emit "grk_${b}_bypass.j2k"        grk_compress -i $s -o $OUT/grk_${b}_bypass.j2k -M 1
  emit "grk_${b}_allmodes.j2k"      grk_compress -i $s -o $OUT/grk_${b}_allmodes.j2k -M 37
done
echo "encoded=$n skipped=$fail"
