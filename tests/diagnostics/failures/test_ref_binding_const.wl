// Test: MUTABLE_REFERENCE_TO_CONST
// File: tests/diagnostics/failures/test_ref_binding_const.wl
// Focus: Preventing a mutable alias from bypassing const access.
// Expected Error: "TypeError: Cannot bind a mutable reference to constant storage."

func main() -> Int {
    const value: Int = 1;
    let alias: Int = ref value;
    return 0;
}
