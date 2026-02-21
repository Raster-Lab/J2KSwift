# J2KSwift CLI Examples

Common workflow examples for the `j2k` command-line tool.

---

## Encoding

### Lossless encoding from PGM

```bash
j2k encode -i input.pgm -o output.j2k --lossless
```

### Lossy encoding at 80 % quality

```bash
j2k encode -i input.ppm -o output.jp2 --quality 0.8
```

### Target bit-rate of 0.5 bits per pixel

```bash
j2k encode -i input.ppm -o output.j2k --bitrate 0.5
```

### Use the `quality` preset with RPCL progression order

```bash
j2k encode -i input.ppm -o output.jp2 --preset quality --progression RPCL
```

### Encode with tiling (256 × 256 tiles)

```bash
j2k encode -i large.ppm -o tiled.jp2 --tile-size 256x256
```

### HTJ2K (Part 15) lossless encoding

```bash
j2k encode -i input.ppm -o output.j2k --htj2k --lossless
```

### Encode and show timing breakdown in JSON

```bash
j2k encode -i input.pgm -o output.j2k --quality 0.9 --json --timing
```

### Quiet encoding (suppress all output on success)

```bash
j2k encode -i input.pgm -o output.j2k --lossless --quiet
```

---

## Decoding

### Basic decode to PPM

```bash
j2k decode -i input.jp2 -o output.ppm
```

### Decode at half resolution (level 1)

```bash
j2k decode -i input.jp2 -o thumbnail.pgm --level 1
```

### Decode only the first quality layer

```bash
j2k decode -i input.j2k -o preview.ppm --layer 1
```

### Decode a single component (e.g. luminance)

```bash
j2k decode -i rgb.j2k -o luma.pgm --component 0
```

### Decode and get JSON metadata

```bash
j2k decode -i input.jp2 -o output.ppm --json
```

---

## Inspecting files

### Show basic image information

```bash
j2k info image.jp2
```

### List all marker segments

```bash
j2k info image.j2k --markers
```

### List JP2 file-format boxes

```bash
j2k info image.jp2 --boxes
```

### JSON output for scripting

```bash
j2k info image.jp2 --json | python3 -m json.tool
```

### Quick validation check

```bash
j2k info image.j2k --validate
echo $?  # 0 = valid, 1 = invalid
```

---

## Transcoding

### Convert Part 1 codestream to HTJ2K

```bash
j2k transcode -i legacy.j2k -o fast.j2k --to-htj2k
```

### Convert HTJ2K back to Part 1

```bash
j2k transcode -i fast.j2k -o compat.j2k --from-htj2k
```

### Re-encode at a lower bit-rate

```bash
j2k transcode -i original.jp2 -o compressed.jp2 --bitrate 0.3
```

### Batch-transcode a directory to HTJ2K

```bash
j2k transcode --batch ./source_images --output-dir ./htj2k_images --to-htj2k
```

### Change container format from J2K to JP2

```bash
j2k transcode -i raw.j2k -o wrapped.jp2 --format jp2
```

---

## Validation

### Basic validation

```bash
j2k validate image.jp2
```

### Part 1 conformance check

```bash
j2k validate image.jp2 --part1
```

### HTJ2K conformance check

```bash
j2k validate fast.j2k --part15
```

### Strict validation with JSON output

```bash
j2k validate image.jp2 --strict --json
```

### Batch validation with a shell loop

```bash
for f in images/*.jp2; do
    j2k validate "$f" --quiet || echo "INVALID: $f"
done
```

---

## Benchmarking

### Simple benchmark (3 runs)

```bash
j2k benchmark -i test.pgm
```

### 10-run benchmark with warmup

```bash
j2k benchmark -i test.ppm -r 10 --warmup 3
```

### Encode-only benchmark saved to CSV

```bash
j2k benchmark -i test.ppm -r 20 --encode-only --format csv -o results.csv
```

### JSON benchmark report

```bash
j2k benchmark -i test.ppm -r 5 --format json -o report.json
```

### Benchmark with quality preset

```bash
j2k benchmark -i test.ppm --preset balanced -r 10
```

---

## Scripting patterns

### Check version in a script

```bash
VERSION=$(j2k --version | awk '{print $3}')
echo "Using J2KSwift $VERSION"
```

### Encode all PGM files in a directory

```bash
for f in images/*.pgm; do
    base="${f%.pgm}"
    j2k encode -i "$f" -o "${base}.jp2" --quality 0.9 --quiet
done
echo "Done"
```

### Validate then decode

```bash
if j2k validate "$INPUT" --quiet; then
    j2k decode -i "$INPUT" -o "$OUTPUT"
else
    echo "Validation failed for $INPUT" >&2
    exit 1
fi
```

### Extract image dimensions using JSON output

```bash
j2k info image.jp2 --json | python3 -c "
import json, sys
info = json.load(sys.stdin)
print(f'{info[\"width\"]}x{info[\"height\"]}')
"
```
