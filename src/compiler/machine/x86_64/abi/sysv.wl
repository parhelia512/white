// src/compiler/machine/x86_64/abi/sysv.wl
import * from "../model.wl"
import * from "../../../wir/model.wl"


struct X86SysVArgCursor(
    integer_index: Int,
    float_index: Int,
    stack_index: Int
)

struct X86ArgLocation(
    register: X86Register,
    stack_offset: Int
)

enum X86SysVClass {
    Empty,
    Integer,
    SSE,
    Memory
}

struct X86SysVTypeClass(
    first: X86SysVClass,
    second: X86SysVClass,
    count: Int,
    size: Int,
    alignment: Int,
    memory: Bool
)

struct X86SysVValueLocation(
    first: X86Register,
    second: X86Register,
    count: Int,
    stack_offset: Int,
    stack_size: Int,
    size: Int,
    first_class: X86SysVClass,
    second_class: X86SysVClass
)

struct X86SysVCallLayout(
    hidden: X86Register,
    arguments: Vector(X86SysVValueLocation),
    stack_size: Int
)

func x86_sysv_merge_class(left: X86SysVClass, right: X86SysVClass) -> X86SysVClass {
    if (left == right || right == X86SysVClass.Empty) { return left; }
    if (left == X86SysVClass.Empty) { return right; }
    if (left == X86SysVClass.Memory || right == X86SysVClass.Memory) {
        return X86SysVClass.Memory;
    }

    if (left == X86SysVClass.Integer || right == X86SysVClass.Integer) {
        return X86SysVClass.Integer;
    }

    return X86SysVClass.SSE;
}

func x86_sysv_merge_range(ref first: X86SysVClass, ref second: X86SysVClass, offset: Int, size: Int, abi_class: X86SysVClass) -> Bool {
// merge one field into the two eightbytes used by the SysV classifier
    if (offset < 0 || size < 0 || offset + size > 16) { return false; }
    if (size == 0) { return true; }

    let first_slot: Int = offset / 8;
    let last_slot: Int = (offset + size - 1) / 8;
    let slot: Int = first_slot;

    while (slot <= last_slot) {
        if (slot == 0) {
            first = x86_sysv_merge_class(first, abi_class);
        } else if (slot == 1) {
            second = x86_sysv_merge_class(second, abi_class);
        } else {
            return false;
        }
        slot++;
    }

    return first != X86SysVClass.Memory && second != X86SysVClass.Memory;
}

func x86_sysv_classify_at(
    ref program: WirModule,
    type_id: WirTypeID,
    layouts: Vector(WirTypeLayout),
    offset: Int,
    ref first: X86SysVClass,
    ref second: X86SysVClass
) -> Bool {
// classify against the final layout, padding belongs to neither class and each
// field may change the class of either eightbyte it overlaps.
    let index: Int = wir_id_index(UInt32(type_id));

    if (index < 0 || index >= program.arena.types.length() || index >= layouts.length()) {
        return false;
    }

    let type: WirType = program.arena.types[index];
    let layout: WirTypeLayout = layouts[index];

    if (!layout.valid || layout.size > 16UL || offset > 16 - Int(layout.size)) {
        return false;
    }

    if (type.kind == WirTypeKind.FloatType) {
        return x86_sysv_merge_range(ref first, ref second, offset, Int(layout.size), X86SysVClass.SSE);
    }

    if (type.kind == WirTypeKind.BoolType || type.kind == WirTypeKind.SignedInt ||
        type.kind == WirTypeKind.UnsignedInt || type.kind == WirTypeKind.Pointer ||
        type.kind == WirTypeKind.Function) {
        return x86_sysv_merge_range(ref first, ref second, offset, Int(layout.size), X86SysVClass.Integer);
    }

    if (type.kind == WirTypeKind.Array) {
        let element_index: Int = wir_id_index(UInt32(type.element));

        if (element_index < 0 || element_index >= layouts.length()) { return false; }

        let element: WirTypeLayout = layouts[element_index];

        if (!element.valid || element.size == 0UL) { return type.length == UIntSize(0); }

        let i: UIntSize = UIntSize(0);

        while (i < type.length) {
            if (!x86_sysv_classify_at(ref program, type.element, layouts, offset + Int(UInt64(i) * element.size), ref first, ref second)) {
                return false;
            }
            i++;
        }

        return true;
    }

    if (type.kind != WirTypeKind.Struct || !type.complete || layout.field_offsets.length() != type.fields.length()) {
        return false;
    }

    let i: Int = 0;

    while (i < type.fields.length()) {
        let field_index: Int = wir_id_index(UInt32(type.fields[i]));

        if (field_index < 0 || field_index >= layouts.length()) { return false; }

        let field: WirTypeLayout = layouts[field_index];
        let field_offset: Int = Int(layout.field_offsets[i]);

        if (!field.valid || field.alignment <= 0 || field_offset % field.alignment != 0) {
            return false;
        }

        if (!x86_sysv_classify_at(ref program, type.fields[i], layouts, offset + field_offset, ref first, ref second)) {
            return false;
        }
        i++;
    }

    return true;
}

func x86_sysv_classify(ref program: WirModule, type_id: WirTypeID, layouts: Vector(WirTypeLayout)) -> X86SysVTypeClass {
// the AMD64 ABI splits values up to sixteen bytes into two eightbytes. Larger
// values, invalid layouts and layouts we cannot describe safely use MEMORY.
    let index: Int = wir_id_index(UInt32(type_id));

    if (index < 0 || index >= layouts.length()) {
        return X86SysVTypeClass(first=X86SysVClass.Memory, second=X86SysVClass.Memory, count=0, size=0, alignment=1, memory=true);
    }

    let layout: WirTypeLayout = layouts[index];

    if (!layout.valid || layout.size > 16UL) {
        return X86SysVTypeClass(first=X86SysVClass.Memory, second=X86SysVClass.Memory, count=0, size=Int(layout.size), alignment=layout.alignment, memory=true);
    }

    let first: X86SysVClass = X86SysVClass.Empty;
    let second: X86SysVClass = X86SysVClass.Empty;

    if (!x86_sysv_classify_at(ref program, type_id, layouts, 0, ref first, ref second)) {
        return X86SysVTypeClass(first=X86SysVClass.Memory, second=X86SysVClass.Memory, count=0, size=Int(layout.size), alignment=layout.alignment, memory=true);
    }

    let count: Int = 0;

    if (layout.size > 0UL) { count = 1; }
    if (layout.size > 8UL) { count = 2; }

    return X86SysVTypeClass(first=first, second=second, count=count, size=Int(layout.size), alignment=layout.alignment, memory=false);
}

func x86_sysv_class_count(type: X86SysVTypeClass, abi_class: X86SysVClass) -> Int {
    let count: Int = 0;

    if (type.count > 0 && type.first == abi_class) { count++; }
    if (type.count > 1 && type.second == abi_class) { count++; }

    return count;
}

func x86_sysv_argument_register(index: Int, floating: Bool) -> X86Register {
    if (index < 0) { return X86Register.None; }
    if floating {
        if (index > 7) { return X86Register.None; }
        if (index == 0) { return X86Register.XMM0; }
        if (index == 1) { return X86Register.XMM1; }
        if (index == 2) { return X86Register.XMM2; }
        if (index == 3) { return X86Register.XMM3; }
        if (index == 4) { return X86Register.XMM4; }
        if (index == 5) { return X86Register.XMM5; }
        if (index == 6) { return X86Register.XMM6; }

        return X86Register.XMM7;
    }

    if (index > 5) { return X86Register.None; }
    if (index == 0) { return X86Register.RDI; }
    if (index == 1) { return X86Register.RSI; }
    if (index == 2) { return X86Register.RDX; }
    if (index == 3) { return X86Register.RCX; }
    if (index == 4) { return X86Register.R8; }

    return X86Register.R9;
}

func x86_sysv_class_register(index: Int, abi_class: X86SysVClass) -> X86Register {
    return x86_sysv_argument_register(index, abi_class == X86SysVClass.SSE);
}

func x86_sysv_return_register(index: Int, abi_class: X86SysVClass) -> X86Register {
    if (abi_class == X86SysVClass.SSE) {
        if (index == 0) { return X86Register.XMM0; }
        if (index == 1) { return X86Register.XMM1; }

        return X86Register.None;
    }

    if (abi_class == X86SysVClass.Integer) {
        if (index == 0) { return X86Register.RAX; }
        if (index == 1) { return X86Register.RDX; }
    }

    return X86Register.None;
}

func x86_sysv_stack_value(ref cursor: X86SysVArgCursor, type: X86SysVTypeClass) -> X86SysVValueLocation {
// reserve an aligned stack home for an argument rejected by either register bank
    let size: Int = type.size;
    let slots: Int = (size + 7) / 8;

    if (type.alignment > 8 && (cursor.stack_index & 1) != 0) {
        cursor.stack_index++;
    }

    let offset: Int = cursor.stack_index * 8;
    cursor.stack_index += slots;

    return X86SysVValueLocation(
        first=X86Register.None,
        second=X86Register.None,
        count=type.count,
        stack_offset=offset,
        stack_size=slots * 8,
        size=size,
        first_class=type.first,
        second_class=type.second
    );
}

func x86_sysv_value_location(ref cursor: X86SysVArgCursor, type: X86SysVTypeClass) -> X86SysVValueLocation {
// register assignment is atomic for one argument. If either register bank is
// exhausted the complete value moves to the stack, not just its last part.
    if (type.memory) {
        return x86_sysv_stack_value(ref cursor, type);
    }

    let integer_count: Int = x86_sysv_class_count(type, X86SysVClass.Integer);
    let float_count: Int = x86_sysv_class_count(type, X86SysVClass.SSE);

    if (cursor.integer_index + integer_count > 6 || cursor.float_index + float_count > 8) {
        return x86_sysv_stack_value(ref cursor, type);
    }

    let first: X86Register = X86Register.None;
    let second: X86Register = X86Register.None;

    if (type.count > 0) {
        if (type.first == X86SysVClass.SSE) {
            first = x86_sysv_class_register(cursor.float_index, type.first);
            cursor.float_index++;
        } else {
            first = x86_sysv_class_register(cursor.integer_index, type.first);
            cursor.integer_index++;
        }
    }

    if (type.count > 1) {
        if (type.second == X86SysVClass.SSE) {
            second = x86_sysv_class_register(cursor.float_index, type.second);
            cursor.float_index++;
        } else {
            second = x86_sysv_class_register(cursor.integer_index, type.second);
            cursor.integer_index++;
        }
    }

    return X86SysVValueLocation(
        first=first,
        second=second,
        count=type.count,
        stack_offset=-1,
        stack_size=0,
        size=type.size,
        first_class=type.first,
        second_class=type.second
    );
}

func x86_plan_sysv_call(
    ref program: WirModule,
    signature: WirType,
    layouts: Vector(WirTypeLayout),
    hidden: Bool,
    ref result: X86SysVCallLayout
) -> Void {
// MEMORY returns consume RDI before ordinary arguments are assigned. Keep this
// in the shared plan so callers and callees cannot disagree about the shift.
    let cursor: X86SysVArgCursor = X86SysVArgCursor(integer_index=0, float_index=0, stack_index=0);
    let hidden_register: X86Register = X86Register.None;

    if hidden {
        hidden_register = x86_sysv_argument_register(cursor.integer_index, false);
        cursor.integer_index++;
    }

    let arguments: Vector(X86SysVValueLocation) = [];
    let i: Int = 0;

    while (i < signature.parameters.length()) {
        let classification: X86SysVTypeClass = x86_sysv_classify(ref program, signature.parameters[i], layouts);
        arguments.append(x86_sysv_value_location(ref cursor, classification));
        i++;
    }

    result.hidden = hidden_register;
    result.arguments = arguments;
    result.stack_size = cursor.stack_index * 8;
}

func x86_sysv_arg(ref cursor: X86SysVArgCursor, floating: Bool) -> X86ArgLocation {
// assign a scalar argument, kept for the older lowering paths which have no full call plan
    let index: Int = cursor.integer_index;

    if floating {
        index = cursor.float_index;
        cursor.float_index += 1;
    } else {
        cursor.integer_index += 1;
    }

    let register: X86Register = x86_sysv_argument_register(index, floating);

    if (register != X86Register.None) {
        return X86ArgLocation(register=register, stack_offset=-1);
    }

    let offset: Int = cursor.stack_index * 8;
    cursor.stack_index += 1;

    return X86ArgLocation(register=X86Register.None, stack_offset=offset);
}
