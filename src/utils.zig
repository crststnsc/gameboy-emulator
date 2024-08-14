fn is_bit_set(data: u8, bit_nr: u4) bool {
    const bit_mask = 0b1 << bit_nr - 1;
    return (data & bit_mask) != 0;
}