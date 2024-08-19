const std = @import("std");
const expect = std.testing.expect;

fn is_bit_set(data: u8, bit_nr: comptime_int) bool {
    const bit_mask = 0b1 << bit_nr - 1;
    return (data & bit_mask) != 0;
}

fn set_bit(data: u8, bit_nr: comptime_int) u8 {
    const bit_mask = 0b1 << bit_nr - 1;
    const new_data = data | bit_mask;
    return new_data;
}

fn reset_bit(data: u8, bit_nr: comptime_int) u8 {
    const bit_mask: u8 = 0b1 << bit_nr - 1;
    const new_data = data & ~bit_mask;
    return new_data;
}

fn get_bit(data: u8, bit_nr: comptime_int) u8 {
    if (is_bit_set(data, bit_nr)) {
        return 1;
    }
    return 0;
}

test "check bit set" {
    const data = 0b00001000;
    try expect(is_bit_set(data, 4) == true);
}

test "set bit" {
    const data = 0b00001000;
    try expect(set_bit(data, 2) == 0b00001010);
}

test "reset bit" {
    const data = 0b11111110;
    try expect(reset_bit(data, 4) == 0b11110110);
}