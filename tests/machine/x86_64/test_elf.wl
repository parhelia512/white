// Test: X86_64_ELF
// File: tests/machine/x86_64/test_elf.wl
// Focus: Encode Linux x86-64 sections, symbols, and RELA relocations.

import * from "../../../src/compiler/machine/x86_64/model.wl"
import elf_object, elf_reloc_data from "../../../src/compiler/machine/x86_64/elf.wl"

func read_u16(bytes: Vector(Byte), offset: Int) -> UInt32 {
    return UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8U);
}

func read_u32(bytes: Vector(Byte), offset: Int) -> UInt32 {
    return UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8U) |
        (UInt32(bytes[offset + 2]) << 16U) | (UInt32(bytes[offset + 3]) << 24U);
}

func read_u64(bytes: Vector(Byte), offset: Int) -> UInt64 {
    return UInt64(read_u32(bytes, offset)) | (UInt64(read_u32(bytes, offset + 4)) << 32UL);
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
    if (read_u32(object, 20) != 1U || read_u16(object, 58) != 64U || read_u16(object, 60) != 7U) {
        print("FAIL: ELF section table is incomplete");
        return 1;
    }
    let relocation_symbols: Dict(String, Int) = Dict();
    relocation_symbols.put("write", 2);
    let relocation_data: Vector(Byte) = elf_reloc_data(
        [X86Relocation(section=".text", offset=1U, kind=X86RelocationKind.Rel32, symbol="write", addend=0L)],
        ".text",
        relocation_symbols,
        symbols
    )?;
    catch(err) {
        print("FAIL: ELF relocation data could not be encoded");
        return 1;
    }
    if (relocation_data.length() != 24 || read_u64(relocation_data, 16) != UInt64(18446744073709551612UL)) {
        print("FAIL: ELF PC-relative relocation did not apply the -4 addend");
        return 1;
    }
    print("PASS: x86_64 ELF object and relocation encoding");
    return 0;
}
