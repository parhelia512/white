// Test: X86_64_SYSV_AGGREGATE_HOST
// File: tests/machine/x86_64/fixtures/sysv_aggregate_host.c
// Focus: Check mixed register classes, exhausted registers and MEMORY aggregates.

#include <stdio.h>

struct Pair { int x, y; };
struct Mixed { double x; int y; };
struct FloatPair { double x, y; };
struct LongPair { long x, y; };
struct Large { long a, b, c; };

extern int pair_sum(struct Pair value);
extern struct Pair pair_make(int x, int y);
extern double mixed_sum(struct Mixed value);
extern struct Mixed mixed_make(double x, int y);
extern struct FloatPair float_pair_make(double x, double y);
extern struct LongPair long_pair_make(long x, long y);
extern long stack_pair(long, long, long, long, long, long, struct LongPair);
extern struct Mixed mixed_relay(struct Mixed value);
extern long large_sum(struct Large value);
extern struct Large large_make(long a, long b, long c);
extern struct Large large_relay(struct Large value);

struct Mixed host_mixed(struct Mixed value) {
    value.x += 1.0;
    value.y += 2;
    return value;
}

struct Large host_large(struct Large value) {
    value.a += 1;
    value.b += 2;
    value.c += 3;
    return value;
}

int main(void) {
    struct Pair pair = pair_make(10, 32);
    if (pair.x != 10 || pair.y != 32 || pair_sum(pair) != 42) return 1;

    struct Mixed mixed = mixed_make(2.5, 4);
    if (mixed.x != 2.5 || mixed.y != 4 || mixed_sum(mixed) != 6.5) return 2;

    struct FloatPair floats = float_pair_make(1.25, -9.5);
    if (floats.x != 1.25 || floats.y != -9.5) return 3;

    struct LongPair longs = long_pair_make(10, 20);
    if (longs.x != 10 || longs.y != 20) return 4;
    if (stack_pair(1, 2, 3, 4, 5, 6, longs) != 51) return 5;

    mixed = mixed_relay(mixed);
    if (mixed.x != 3.5 || mixed.y != 6) return 6;

    struct Large large = large_make(10, 20, 12);
    if (large.a != 10 || large.b != 20 || large.c != 12 || large_sum(large) != 42) return 7;

    large = large_relay(large);
    if (large.a != 11 || large.b != 22 || large.c != 15) return 8;

    puts("PASS: SysV aggregate ABI");
    return 0;
}
