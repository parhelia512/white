// src/compiler/machine/x86_64/abi.wl
import * from "model.wl"
import * from "../../wir/model.wl"

// the backend starts with Win64, but the machine code itself does not depend
// on the object format. Keep the selected calling convention here so lowering
// can share the instruction emitter between COFF and ELF.
let __x86_sysv_abi: Bool = false;

func x86_set_sysv_abi(value: Bool) -> Void {
    __x86_sysv_abi = value;
}

func x86_is_sysv_abi() -> Bool {
    return __x86_sysv_abi;
}


func x86_win64_aggregate_size(layout: WirTypeLayout) -> Int {
// small POD aggregates use integer registers, even when their fields are floats
    if (!layout.valid) { return 0; }
    if (layout.size == 1UL || layout.size == 2UL || layout.size == 4UL || layout.size == 8UL) {
        return Int(layout.size);
    }
    return 0;
}

struct X86Win64ABI(
    pointer_bits: Int,
    stack_alignment: Int,
    shadow_space: Int,
    integer_arguments: Vector(X86Register),
    floating_arguments: Vector(X86Register),
    callee_saved: Vector(X86Register)
)

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

func x86_sysv_class_register(index: Int, abi_class: X86SysVClass) -> X86Register {
    return x86_argument_register(index, abi_class == X86SysVClass.SSE);
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
        hidden_register = x86_argument_register(cursor.integer_index, false);
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
    let index: Int = cursor.integer_index;
    if floating {
        index = cursor.float_index;
        cursor.float_index += 1;
    } else {
        cursor.integer_index += 1;
    }
    let register: X86Register = x86_argument_register(index, floating);
    if (register != X86Register.None) {
        return X86ArgLocation(register=register, stack_offset=-1);
    }
    let offset: Int = cursor.stack_index * 8;
    cursor.stack_index += 1;
    return X86ArgLocation(register=X86Register.None, stack_offset=offset);
}

func x86_win64_abi() -> X86Win64ABI {
// Win64 has four argument positions, not four integer plus four float args.
    // Keep both lists together, callers and callees must count positions the same way.
    return X86Win64ABI(
        pointer_bits=64,
        stack_alignment=16,
        shadow_space=32,
        integer_arguments=[X86Register.RCX, X86Register.RDX, X86Register.R8, X86Register.R9],
        floating_arguments=[X86Register.XMM0, X86Register.XMM1, X86Register.XMM2, X86Register.XMM3],
        callee_saved=[
            X86Register.RBX, X86Register.RBP, X86Register.RDI, X86Register.RSI, X86Register.RSP,
            X86Register.R12, X86Register.R13, X86Register.R14, X86Register.R15,
            X86Register.XMM6, X86Register.XMM7, X86Register.XMM8, X86Register.XMM9,
            X86Register.XMM10, X86Register.XMM11, X86Register.XMM12, X86Register.XMM13,
            X86Register.XMM14, X86Register.XMM15
        ]
    );
}

func x86_win64_argument_register(index: Int, floating: Bool) -> X86Register {
// this runs for each call argument, building the full ABI description here
    // would allocate three vectors just to select one of four registers.
    if (index < 0 || index >= 4) { return X86Register.None; }

    if floating {
        if (index == 0) { return X86Register.XMM0; }
        if (index == 1) { return X86Register.XMM1; }
        if (index == 2) { return X86Register.XMM2; }
        return X86Register.XMM3;
    }
    if (index == 0) { return X86Register.RCX; }
    if (index == 1) { return X86Register.RDX; }
    if (index == 2) { return X86Register.R8; }
    return X86Register.R9;
}

func x86_win64_stack_arg_offset(index: Int) -> Int {
    if (index < 4) { return -1; }

    // the first 32 bytes belong to the four register arguments
    return 32 + (index - 4) * 8;
}

func x86_win64_stack_param_offset(index: Int) -> Int {
    if (index < 4) { return -1; }

    // return address and saved RBP put the same argument 16 bytes farther away
    return 48 + (index - 4) * 8;
}

func x86_win64_call_frame(argument_count: Int) -> Int {
    let size: Int = 32;
    if (argument_count > 4) { size += (argument_count - 4) * 8; }
    return (size + 15) & -16;
}

func x86_win64_is_callee_saved(register: X86Register) -> Bool {
    let abi: X86Win64ABI = x86_win64_abi();

    let i: Int = 0;
    while (i < abi.callee_saved.length()) {
        if (abi.callee_saved[i] == register) { return true; }
        i++;
    }

    return false;
}

func x86_aggregate_size(layout: WirTypeLayout) -> Int {
    return x86_win64_aggregate_size(layout);
}

func x86_argument_register(index: Int, floating: Bool) -> X86Register {
    if (!__x86_sysv_abi) {
        return x86_win64_argument_register(index, floating);
    }
    if (index < 0) { return X86Register.None; }
    if (floating) {
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

func x86_stack_arg_offset(index: Int) -> Int {
    if (!__x86_sysv_abi) { return x86_win64_stack_arg_offset(index); }
    if (index < 6) { return -1; }
    return (index - 6) * 8;
}

func x86_stack_param_offset(index: Int) -> Int {
    if (!__x86_sysv_abi) { return x86_win64_stack_param_offset(index); }
    if (index < 6) { return -1; }
    return 16 + (index - 6) * 8;
}

func x86_call_frame(argument_count: Int) -> Int {
    if (!__x86_sysv_abi) { return x86_win64_call_frame(argument_count); }
    let staged: Int = 64;
    if (argument_count > 8) { staged += (argument_count - 8) * 8; }
    let size: Int = staged;
    return (size + 15) & -16;
}
