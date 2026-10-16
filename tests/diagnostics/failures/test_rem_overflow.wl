// Test: SIGNED_REMAINDER_OVERFLOW
// File: tests/diagnostics/failures/test_rem_overflow.wl
// Focus: Reporting the signed remainder pair that faults on native division hardware.
// Expected Error: "RuntimeError: Signed division overflow"

func main() -> Int {
    let minimum: Long = -9223372036854775807L - 1L;
    let negative_one: Long = -1L;
    print(minimum % negative_one);
    return 0;
}
