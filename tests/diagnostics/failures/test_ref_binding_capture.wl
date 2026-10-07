// Test: REFERENCE_BINDING_CAPTURE
// File: tests/diagnostics/failures/test_ref_binding_capture.wl
// Focus: Preventing a local reference binding from escaping in a closure.
// Expected Error: "TypeError: Cannot capture reference binding 'alias'."

func main() -> Int {
    let value: Int = 0;
    let alias: Int = ref value;

    func write() -> Void {
        alias = 1;
    }
    return 0;
}
