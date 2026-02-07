// Let me think through this more carefully
// The encoder and decoder are processing position 3 the same way
// They both encode/decode sig=false for position 3
// But position 3 ends up with 1 instead of 0

// This could happen if:
// 1. The bits are being read from the wrong bitstream positions
// 2. Position 3 is being processed an additional time somewhere
// 3. There's a refinement bit being applied to position 3

// Let me check: is position 3 ever marked as .significant?
// If not, it can't be processed in the magnitude refinement pass

// So the question is: where does the value 1 come from?
// If position 3 is never significant and never refined,
// how does it get magnitude 1?

print("Analysis:")
print("1. Position 3 encodes sig=false in both SPP and cleanup")
print("2. Position 3 is never marked as .significant")
print("3. In magnitude refinement, only .significant coefficients are processed")
print("4. So position 3 should remain 0")
print("")
print("But the test shows position 3 = 1")
print("")
print("Possibilities:")
print("1. Position 3 IS being marked significant somewhere (encoder marks it, decoder doesn't)")
print("2. Position 3 IS being processed in magnitude refinement despite not being marked")
print("3. The bits are getting misaligned and reading the wrong values")
print("4. Position 3 is being processed in cleanup pass individually in encoder, ")
print("   but RLC-skipped in decoder (or vice versa)")

