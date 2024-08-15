const std = @import("std");
const expect = std.testing.expect;

fn is_bit_set(data: u8, bit_nr: comptime_int) bool {
    const bit_mask = 0b1 << bit_nr - 1;
    return (data & bit_mask) != 0;
}

test "check bit set" {
    const data = 0b00001000;
    try expect(is_bit_set(data, 4) == true);
}
