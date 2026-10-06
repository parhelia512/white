// Test: INTEGER_ABS_IDIOM
// File: tests/language/types/test_abs_idiom.wl
// Focus: Branch and two's-complement forms of absolute value produce the same wrapping result.

func abs_branch(value: Int) -> Int {
    if (value < 0) {
        return -value;
    }
    return value;
}

func abs_bits(value: Int) -> Int {
    let mask = value >> 31;
    return (value + mask) ^ mask;
}

func main() -> Int {
    let minimum: Int = -2147483647 - 1;
    if (abs_branch(-42) != 42 || abs_branch(0) != 0 || abs_branch(17) != 17 || abs_branch(minimum) != minimum) {
        print("FAIL: Branch absolute value");
        return 1;
    }
    if (abs_bits(-42) != 42 || abs_bits(0) != 0 || abs_bits(17) != 17 || abs_bits(minimum) != minimum) {
        print("FAIL: Bitwise absolute value");
        return 1;
    }
    print("PASS: Integer absolute value idioms");
    return 0;
}
