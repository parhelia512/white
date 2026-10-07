// Test: X86_64_ELF
// File: tests/machine/x86_64/test_elf.wl
// Focus: Encode Linux x86-64 sections, symbols, and RELA relocations.

import * from "../../../src/compiler/machine/x86_64/model.wl"
import elf_object from "../../../src/compiler/machine/x86_64/elf.wl"

func read_u16(bytes: Vector(Byte), offset: Int) -> UInt32 {
    return UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8U);
}

func read_u32(bytes: Vector(Byte), offset: Int) -> UInt32 {
    return UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8U) |
        (UInt32(bytes[offset + 2]) << 16U) | (UInt32(bytes[offset + 3]) << 24U);
}

func main() -> Int {
    let text: X86CodeSection = X86CodeSection(name=".text", bytes=[Byte(232), Byte(0), Byte(0), Byte(0), Byte(0), Byte(195)], alignment=16, executable=true, writable=false);
    let symbols: Vector(X86Symbol) = [
        X86Symbol(name="main", section=".text", offset=0U, external=true),
        X86Symbol(name="write", section="", offset=0U, external=true)
    ];
    let relocations: Vector(X86Relocation) = [
        X86Relocation(section=".text", offset=1U, kind=X86RelocationKind.Rel32, symbol="write", addend=-4L)
    ];
    let object: Vector(Byte) = elf_object(X86Object(sections=[text], symbols=symbols, relocations=relocations))?;
    catch(err) {
        print("FAIL: ELF object encoding failed");
        return 1;
    }
    if (object.length() < 64 || object[0] != Byte(127) || object[1] != Byte(69) || object[2] != Byte(76) || object[3] != Byte(70)) {
        print("FAIL: ELF identification is invalid");
        return 1;
    }
    if (object[4] != Byte(2) || object[5] != Byte(1) || read_u16(object, 16) != 1U || read_u16(object, 18) != 62U) {
        print("FAIL: ELF header does not describe an x86-64 relocatable object");
        return 1;
    }
    if (read_u32(object, 20) != 1U || read_u16(object, 58) != 64U || read_u16(object, 60) != 6U) {
        print("FAIL: ELF section table is incomplete");
        return 1;
    }
    print("PASS: x86_64 ELF object and relocation encoding");
    return 0;
}
