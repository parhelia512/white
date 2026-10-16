// src/compiler/machine/x86_64/abi.wl
import X86Register from "model.wl"
import WirTypeLayout from "../../wir/model.wl"
import x86_win64_aggregate_size, x86_win64_argument_register, x86_win64_stack_arg_offset, x86_win64_stack_param_offset, x86_win64_call_frame from "abi/win64.wl"
import x86_sysv_argument_register from "abi/sysv.wl"


// lowering is shared by COFF and ELF. This switch only selects the platform
// ABI used by the small dispatch functions below.
let __x86_sysv_abi: Bool = false;

func x86_set_sysv_abi(value: Bool) -> Void {
    __x86_sysv_abi = value;
}

func x86_is_sysv_abi() -> Bool {
    return __x86_sysv_abi;
}

func x86_aggregate_size(layout: WirTypeLayout) -> Int {
    return x86_win64_aggregate_size(layout);
}

func x86_argument_register(index: Int, floating: Bool) -> X86Register {
    if (__x86_sysv_abi) {
        return x86_sysv_argument_register(index, floating);
    }
    return x86_win64_argument_register(index, floating);
}

func x86_stack_arg_offset(index: Int) -> Int {
    if (!__x86_sysv_abi) {
        return x86_win64_stack_arg_offset(index);
    }
    if (index < 6) { return -1; }
    return (index - 6) * 8;
}

func x86_stack_param_offset(index: Int) -> Int {
    if (!__x86_sysv_abi) {
        return x86_win64_stack_param_offset(index);
    }
    if (index < 6) { return -1; }
    return 16 + (index - 6) * 8;
}

func x86_call_frame(argument_count: Int) -> Int {
    if (!__x86_sysv_abi) {
        return x86_win64_call_frame(argument_count);
    }

    let staged: Int = 64;
    if (argument_count > 8) { staged += (argument_count - 8) * 8; }
    return (staged + 15) & -16;
}
