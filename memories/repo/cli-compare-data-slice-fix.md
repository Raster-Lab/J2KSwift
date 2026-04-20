# CLI compare Data slice fix

- Root cause: PGM loader returned a sliced Data buffer with a non-zero start index.
- Symptom: compare command trapped in Foundation Data subscript when indexing from 0..<count.
- Fix: normalize PGM pixel data with a fresh Data copy and use withUnsafeBytes in metric computation.
- Regression covered in J2KCLITests with a sliced-buffer metrics test.
