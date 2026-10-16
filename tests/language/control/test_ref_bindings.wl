// Test: REFERENCE_BINDINGS
// File: tests/language/control/test_ref_bindings.wl
// Focus: Local reference bindings alias stable storage without becoming pointers.

struct Pair(left: Int, right: Int)

class Cell {
    let value: Int;

    init(value: Int) {
        self.value = value;
    }
}

func add_one(ref value: Int) -> Void {
    value++;
}

func main() -> Int {
    let number: Int = 1;
    let number_ref: Int = ref number;
    number_ref = 7;

    let inferred = ref number;
    inferred++;
    let chained = ref inferred;
    add_one(ref chained);
    const read_only: Int = ref number;

    let pair: Pair = Pair(2, 3);
    let left: Int = ref pair.left;
    left = 9;

    let values: Int[2] = [4, 5];
    let second: Int = ref values[1];
    second = 11;

    let cell: Cell = Cell(10);
    let cell_ref: Cell = ref cell;
    cell_ref = Cell(12);

    if (number != 9 || read_only != 9 || pair.left != 9 || values[1] != 11 || cell.value != 12) {
        print("FAIL: Reference bindings");
        return 1;
    }
    print("PASS: Reference bindings");
    return 0;
}
