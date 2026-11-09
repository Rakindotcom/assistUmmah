"""Prevent flavor packaging from silently reusing an older Dart snapshot."""
import struct
import unittest

from verify_android_bundle import elf_build_id, verify_compiled_aot


def elf(bits, build_id, *, extra_nonload_data=b''):
    header = bytearray(64 if bits == 64 else 52)
    header[:6] = b'\x7fELF' + bytes([2 if bits == 64 else 1, 1])
    note = struct.pack('<III', 4, len(build_id), 3) + b'GNU\0' + build_id
    note += bytes((-len(build_id)) % 4)
    ph_size = 56 if bits == 64 else 32
    note_offset = len(header) + ph_size
    if bits == 64:
        struct.pack_into('<Q', header, 32, len(header))
        struct.pack_into('<HH', header, 54, ph_size, 1)
        ph = struct.pack('<IIQQQQQQ', 4, 0, note_offset, 0, 0, len(note), len(note), 4)
    else:
        struct.pack_into('<I', header, 28, len(header))
        struct.pack_into('<HH', header, 42, ph_size, 1)
        ph = struct.pack('<IIIIIIII', 4, note_offset, 0, 0, len(note), len(note), 0, 4)
    return bytes(header) + ph + note + extra_nonload_data


class CompiledAotIdentityTest(unittest.TestCase):
    def test_symbol_stripping_can_change_file_without_changing_build_id(self):
        for bits in [32, 64]:
            with self.subTest(bits=bits):
                packaged = elf(bits, b'current-snapshot')
                compiled = elf(bits, b'current-snapshot', extra_nonload_data=b'debug-symbols')
                self.assertEqual(verify_compiled_aot(packaged, compiled), b'current-snapshot'.hex())

    def test_stale_packaging_is_rejected_even_with_matching_abi(self):
        for bits in [32, 64]:
            with self.subTest(bits=bits):
                with self.assertRaisesRegex(AssertionError, 'Stale packaged Dart library'):
                    verify_compiled_aot(elf(bits, b'older-snapshot!!'), elf(bits, b'current-snapshot'))

    def test_missing_note_is_not_proof(self):
        data = bytearray(elf(64, b'current-snapshot'))
        struct.pack_into('<H', data, 56, 0)
        with self.assertRaisesRegex(ValueError, 'Missing GNU build ID'):
            elf_build_id(bytes(data))

    def test_truncated_note_is_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Truncated ELF note'):
            elf_build_id(elf(64, b'current-snapshot')[:-1])


if __name__ == '__main__':
    unittest.main()
