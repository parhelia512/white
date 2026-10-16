// Test: X86_64_SYSV_AGGREGATE_FIXTURE
// File: tests/machine/x86_64/fixtures/sysv_aggregate.wl
// Focus: SysV aggregate arguments and returns in both directions across a C boundary.

struct Pair(x: Int, y: Int)
struct Mixed(x: Float, y: Int)
struct FloatPair(x: Float, y: Float)
struct LongPair(x: Long, y: Long)
struct Large(a: Long, b: Long, c: Long)

extern "C" {
    func host_mixed(value: Mixed) -> Mixed;
    func host_large(value: Large) -> Large;
}

@ExportLib
func pair_sum(value: Pair) -> Int {
    return value.x + value.y;
}

@ExportLib
func pair_make(x: Int, y: Int) -> Pair {
    return Pair(x=x, y=y);
}

@ExportLib
func mixed_sum(value: Mixed) -> Float {
    return value.x + Float(value.y);
}

@ExportLib
func mixed_make(x: Float, y: Int) -> Mixed {
    return Mixed(x=x, y=y);
}

@ExportLib
func float_pair_make(x: Float, y: Float) -> FloatPair {
    return FloatPair(x=x, y=y);
}

@ExportLib
func long_pair_make(x: Long, y: Long) -> LongPair {
    return LongPair(x=x, y=y);
}

@ExportLib
func stack_pair(a: Long, b: Long, c: Long, d: Long, e: Long, f: Long, value: LongPair) -> Long {
    return a + b + c + d + e + f + value.x + value.y;
}

@ExportLib
func mixed_relay(value: Mixed) -> Mixed {
    return host_mixed(value);
}

@ExportLib
func large_sum(value: Large) -> Long {
    return value.a + value.b + value.c;
}

@ExportLib
func large_make(a: Long, b: Long, c: Long) -> Large {
    return Large(a=a, b=b, c=c);
}

@ExportLib
func large_relay(value: Large) -> Large {
    return host_large(value);
}
