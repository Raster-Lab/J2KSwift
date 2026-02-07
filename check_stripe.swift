// Check stripe processing

let height = 4
let stripeHeight = 4

for stripeY in stride(from: 0, to: height, by: stripeHeight) {
    let stripeEnd = min(stripeY + stripeHeight, height)
    print("Stripe: stripeY=\(stripeY), stripeEnd=\(stripeEnd)")
    for y in stripeY..<stripeEnd {
        print("  Row \(y)")
    }
}

