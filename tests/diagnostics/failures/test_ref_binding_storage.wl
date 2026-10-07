// Test: UNSTABLE_REFERENCE_BINDING
// File: tests/diagnostics/failures/test_ref_binding_storage.wl
// Focus: Rejecting aliases to storage invalidated by container growth.
// Expected Error: "TypeError: Cannot bind a reference to storage that may move or be released."

func main() -> Int {
    let values: Vector(Int) = [1, 2];
    let first: Int = ref values[0];
    return 0;
}
