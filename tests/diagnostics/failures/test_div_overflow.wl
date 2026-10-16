// Test: SIGNED_DIVISION_OVERFLOW
// File: tests/diagnostics/failures/test_div_overflow.wl
// Focus: Reporting the one signed division pair that the result type cannot represent.
// Expected Error: "RuntimeError: Signed division overflow"

func main() -> Int {
    let minimum: Int = -2147483647 - 1;
    let negative_one: Int = -1;
    print(minimum / negative_one);
    return 0;
}
