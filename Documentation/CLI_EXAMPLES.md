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

---

## Recommended Presets

### Archival / Medical (lossless, maximum fidelity)

```bash
j2k encode -i scan.tiff -o archive.jp2 --lossless --levels 6 --layers 10 \
    --progression RPCL --precincts 256x256
```

### Professional Photography (high quality, moderate file size)

```bash
j2k encode -i photo.png -o output.jp2 --quality 0.95 --preset quality \
    --progression RPCL
```

### Web Delivery (small file, fast decode)

```bash
j2k encode -i image.ppm -o web.jp2 --quality 0.80 --preset fast \
    --progression LRCP
```

### High-Throughput Pipeline (HTJ2K)

```bash
j2k encode -i frame.ppm -o output.jph --codec htj2k-lossless
j2k encode -i frame.ppm -o output.jph --codec htj2k-lossy --quality 0.90
```

### DCI (Digital Cinema Initiative)

```bash
j2k encode -i frame.ppm -o cinema.j2k --bitrate 1.25 --levels 5 \
    --blocksize 32x32 --progression CPRL
```

### Batch Codec Conversion

```bash
j2k transcode --batch ./legacy/ --output-dir ./htj2k/ --codec htj2k-lossless-rpcl
```

---

## Best-Practice Workflows

### Round-Trip Verification

Encode and immediately verify lossless round-trip:

```bash
j2k encode -i original.ppm -o encoded.j2k --lossless
j2k decode -i encoded.j2k -o decoded.ppm
diff <(xxd original.ppm) <(xxd decoded.ppm) && echo "Round-trip OK"
```

### Quality Comparison

Encode at multiple quality settings and compare:

```bash
for q in 0.70 0.80 0.90 0.95 1.0; do
    j2k encode -i input.ppm -o "q${q}.jp2" --quality "$q" --quiet
    echo "q=$q => $(stat -f%z "q${q}.jp2") bytes"
done
```

### Encode + Validate + Benchmark

Full pipeline for production verification:

```bash
j2k encode -i input.ppm -o output.jp2 --preset quality --timing
j2k validate output.jp2 --strict
j2k benchmark -i input.ppm --preset quality -r 5 --format json -o bench.json
```

### Header-Only Inspection

Quickly inspect a codestream without decoding:

```bash
j2k decode -i mystery.j2k --header-only --json
```

### TIFF / PNG Workflows

```bash
# Encode from TIFF
j2k encode -i photograph.tiff -o output.jp2 --quality 0.95

# Decode to PNG
j2k decode -i encoded.jp2 -o output.png

# DICOM medical workflow
j2k encode -i scan.dcm -o scan.jp2 --lossless --levels 6
```

### Piping (stdin/stdout)

```bash
# Pipe from another tool
convert input.bmp ppm:- | j2k encode -i - -o output.jp2 --quality 0.9

# Pipe decode output
j2k decode -i input.jp2 -o - | display -
```
