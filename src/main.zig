const std = @import("std");
const utils = @import("utils.zig");
const rl = @cImport(@cInclude("raylib.h"));


const Register = struct {
    reg: u16,

    pub fn lo(self: *Register) *u8 {
        return @ptrCast(self);
    }

    pub fn hi(self: *Register) *u8 {
        return @ptrCast(@as(*u8, @ptrFromInt(@intFromPtr(self) + 1)));
    }
};


const Emulator = struct {
    screen_data: [160][144][3]u8,
    memory: [0x10000]u8,
    program_counter: u16,

    // The stack pointer is modeled as a register
    // because some opcodes use the hi and lo bits of the stack pointer
    stack_pointer: Register,

    // Registers
    register_af: Register,
    register_bc: Register,
    register_de: Register,
    register_hl: Register,

    // Cartridge
    cartridge_memory: [0x200000]u8,

    // Memory banking type used by the game (DEFAULT: NONE)
    memory_bank_type: MemoryBankType = MemoryBankType.NONE,
    rom_banking: bool,
    current_rom_bank: u8,

    enable_ram: bool,

    ram_banks: [0x8000]u8,
    current_ram_bank: u8,

    timer_counter: u16,
    divider_register: u8,
    divider_counter: u8 = 0,

    interrupt_master: bool,

    scanline_counter: u16,

    pub fn update() void {
        // const max_cycles = 69905;
        // var cycles_this_update = 0;

        // while (cycles_this_update < max_cycles) {
            // TODO const cycles = self.execute_next_opcode();
            // cycles_this_update += cycles;
            // self.update_timers(cycles);
            // self.update_graphics(cycles);
            // TODO self.do_interrupts();
        // }

        // TODO self.render_screen();
    }

    pub fn init(self: *Emulator) Emulator {
        // when the emulator starts we must set the state of registers,
        // the stack pointer, program counter and some memory registers
        self.program_counter = 0x100;
        self.stack_pointer = 0xFFFE;

        self.init_memory();
        self.init_registers();

        // read the memory banking from the cartridge
        self.read_memory_banking_type();
        self.current_rom_bank = 1;
        self.current_ram_bank = 0;

        @memset(&self.ram_banks, 0);
    }

    fn init_memory(self: *Emulator) void {
        self.memory[0xFF05] = 0x00;
        self.memory[0xFF06] = 0x00;
        self.memory[0xFF07] = 0x00;
        self.memory[0xFF10] = 0x80;
        self.memory[0xFF11] = 0xBF;
        self.memory[0xFF12] = 0xF3;
        self.memory[0xFF14] = 0xBF;
        self.memory[0xFF16] = 0x3F;
        self.memory[0xFF17] = 0x00;
        self.memory[0xFF19] = 0xBF;
        self.memory[0xFF1A] = 0x7F;
        self.memory[0xFF1B] = 0xFF;
        self.memory[0xFF1C] = 0x9F;
        self.memory[0xFF1E] = 0xBF;
        self.memory[0xFF20] = 0xFF;
        self.memory[0xFF21] = 0x00;
        self.memory[0xFF22] = 0xFF;
        self.memory[0xFF23] = 0xBF;
        self.memory[0xFF24] = 0x77;
        self.memory[0xFF25] = 0xF3;
        self.memory[0xFF26] = 0xF1;
        self.memory[0xFF40] = 0x91;
        self.memory[0xFF42] = 0x00;
        self.memory[0xFF43] = 0x00;
        self.memory[0xFF45] = 0x00;
        self.memory[0xFF47] = 0xFC;
        self.memory[0xFF48] = 0xFF;
        self.memory[0xFF49] = 0xFF;
        self.memory[0xFF4A] = 0x00;
        self.memory[0xFF4B] = 0x00;
        self.memory[0xFFFF] = 0x00;
    }

    fn init_registers(self: *Emulator) void {
        self.register_af = 0x01B0;
        self.register_bc = 0x0013;
        self.register_de = 0x00D8;
        self.register_hl = 0x014D;
    }

    fn update_timers(self: *Emulator, cycles: u8) void {
        self.update_divier_register(cycles);

        if (self.is_clock_enabled()) {
            self.timer_counter -= cycles;

            if (self.timer_counter <= 0) {
                self.set_clock_freq();

                const TIMA = Time.TIMA.get();
                if (self.read_memory(TIMA) == 255) {
                    self.write_memory(TIMA, self.read_memory(TIMA));
                    self.request_interrupt(2);
                } else {
                    self.write_memory(TIMA, self.read_memory(TIMA) + 1);
                }
            }
        }
    }

    fn is_clock_enabled(self: Emulator) bool {
        // the second bit in the time controller specifies if 
        // the clock is enabled
        const time_controller = self.read_memory(Time.TMC.get());
        return utils.is_bit_set(time_controller, 2);
    }

    fn get_clock_freq(self: Emulator) u8 {
        return self.read_memory(Time.TMC.get()) & 0x3;
    }

    fn set_clock_freq(self: *Emulator) void {
        const freq = self.get_clock_freq();
        switch (freq) {
            0 => {
                self.timer_counter = 1024;
            },
            1 => {
                self.timer_counter = 16;
            },
            2 => {
                self.timer_counter = 64;
            },
            3 => {
                self.timer_counter = 256;
            }
        }
    }

    fn update_divier_register(self: *Emulator, cycles: u8) void {
        self.divider_register += cycles;
        if (self.divider_counter >= 255) {
            self.divider_counter = 0;
            self.memory[0xFF04] += 1;
        }
    }

    fn request_interrupt(self: *Emulator, id: u8) void {
        var request = self.read_memory(0xFF0F);
        request = utils.set_bit(request, id);
        self.write_memory(0xFF0F, request);
    }

    fn check_interrupts(self: *Emulator) void {
        if (self.interrupt_master == false) {
            return;
        }

        const req = self.read_memory(0xFF0F);
        const enabled = self.read_memory(0xFFFF);
        if (req == 0) {
            return;
        }

        for (0..4) |i| {
            if (utils.is_bit_set(req, i) == false) {
                return;
            }

            if (utils.is_bit_set(enabled, i) == true) {
                self.service_interrupt(i);
            }
        }
    }

    fn service_interrupt(self: *Emulator, interrupt: u8) void {
        self.interrupt_master = false;

        var request = self.read_memory(0xFF0F);
        request = utils.reset_bit(request, interrupt);
        self.write_memory(0xFF0F, request);

        switch (interrupt) {
            0 => {
                self.program_counter = 0x40;
            },
            1 => {
                self.program_counter = 0x48;
            },
            2 => {
                self.program_counter = 0x50;
            },
            4 => {
                self.program_counter = 0x60;
            },
        }

        // TODO push address to stack
    }

    fn write_memory(self: *Emulator, address: u16, data: u8) void {
        switch (address) {
            // ROM area: handle banking
            0x0000...0x7FFF => {
                self.handle_banking(address, data);
            },

            // RAM area: handle RAM writing
            0xA000...0xBFFF => {
                if (self.enable_ram) {
                    const new_address = address - 0xA000;
                    self.ram_banks[new_address + (self.current_ram_bank * 0x2000)] = data;
                }
            },

            // Restricted memory area
            0xFEA0...0xFEFF => {
                // TODO some warning
            },

            // ECHO area: mirror writes to both ECHO and RAM
            0xE000...0xFDFF => {
                self.memory[address] = data;
                self.write_memory(address - 0x2000, data);
            },

            // Timer control memory area
            Time.TMC.get() => {
                const freq = self.get_clock_freq();
                self.memory[address] = data;
                const new_freq = self.get_clock_freq();

                if (freq != new_freq) {
                    self.set_clock_freq();
                }
            },

            // trap the divider register
            0xFF04 => {
                self.memory[address] = 0;
            },

            // launch DMA
            0xFF45 => {
                self.dma_transfer(data);
            },

            // Default: write to memory directly
            else => {
                self.memory[address] = data;
            },
        }
    }

    fn draw_scan_line(self: *Emulator) void {
        const lcd_control_register = self.read_memory(0xFF40);
        if (utils.is_bit_set(lcd_control_register, 0)) {
            self.render_tiles();
        }
        if (utils.is_bit_set(lcd_control_register, 1)) {
            self.render_sprites();
        }
    }

    fn render_tiles(self: *Emulator) void {
        var tile_data = 0;
        var background_memory = 0;
        var unsigned = true;

        const scroll_y = self.read_memory(0xFF42);
        const scroll_x = self.read_memory(0xFF43);
        const window_y = self.read_memory(0xFF4A);
        const window_x = self.read_memory(0xFF4B) - 7;

        var using_window = false;

        const lcd_control_register = self.read_memory(0xFF40);
        if (utils.is_bit_set(lcd_control_register, 5)) {
            if (window_y <= self.read_memory(0xFF44)) {
                using_window = true;
            }
        }

        if (utils.is_bit_set(lcd_control_register, 4)) {
            tile_data = 0x8000;
        } else {
            tile_data = 0x8800;
            unsigned = false;
        }

        if (using_window == false) {
            background_memory = if (utils.is_bit_set(lcd_control_register, 3)) 0x9C00 else 0x9800;
        } else {
            background_memory = if (utils.is_bit_set(lcd_control_register, 6)) 0x9C00 else 0x9800;
        }

        var pos_y = 0;
        if (using_window == false) {
            pos_y = scroll_y + self.read_memory(0xFF44);
        } else {
            pos_y = self.read_memory(0xFF44) - window_y;
        }

        const tile_row: u16 = (pos_y / 8) * 32;
        
        for (0..159) |pixel| {
            var pos_x = pixel + scroll_x;

            if (using_window and pixel >= window_x) {
                pos_x = pixel - window_x;
            }

            const tile_col: u16 = pos_x / 8;
            var tile_num = undefined;

            const tile_address = background_memory + tile_row + tile_col;
            if (unsigned) {
                tile_num = self.read_memory(tile_address);
            } else {
                tile_num = @as(i8, self.read_memory(tile_address));
            }

            var tile_location = tile_data;
            if (unsigned) {
                tile_location += tile_num * 16;
            } else {
                tile_location += (tile_num + 128) * 16;
            }

            var line = pos_y % 8;
            line *= 2;

            const data1 = self.read_memory(tile_location + line);
            const data2 = self.read_memory(tile_location + line + 1);

            var color_bit = pos_x % 8;
            color_bit -=  7;
            color_bit *= -1;

            var color_num = if (utils.is_bit_set(data2, color_bit)) 1 else 0;
            const color_num_2 = if (utils.is_bit_set(data1, color_bit)) 1 else 0;
            color_num <<= 1;
            color_num |= color_num_2;

            const color = self.get_color(color_num, 0xFF47);
            const row = self.read_memory(0xFF44);

            self.screen_data[pixel][row][0] = color.red;
            self.screen_data[pixel][row][1] = color.green;
            self.screen_data[pixel][row][2] = color.blue;
        }
    }

    fn render_sprites(self: *Emulator) void {
        const lcd_control_register = self.read_memory(0xFF40);

        const use_8x16 = utils.is_bit_set(lcd_control_register, 2);

        for (0..39) |sprite| {
            const index = sprite * 4;
            const pos_y = self.read_memory(0xFE00 + index) - 16;
            const pos_x = self.read_memory(0xFE00 + index + 1) - 8;
            const tile_location = self.read_memory(0xFE00 + index + 2);
            const attributes = self.read_memory(0xFE00 + index + 3);

            const flip_y = utils.is_bit_set(attributes, 6);
            const flip_x = utils.is_bit_set(attributes, 5);

            const scanline = self.read_memory(0xFF44);
            const size_y = if (use_8x16) 16 else 8;

            if (scanline >= pos_y and scanline < (pos_y + size_y)) {
                var line = scanline - pos_y;

                if (flip_y) {
                    line -= size_y;
                    line *= -1;
                }

                line *= 2;
                const data_address = 0x8000 + (tile_location * 16) + line;
                const data1 = self.read_memory(data_address);
                const data2 = self.read_memory(data_address + 1);

                var tile_pixel = 7;
                while (tile_pixel >= 0) : (tile_pixel -= 1) {
                    var color_bit = tile_pixel;
                    if (flip_x) {
                        color_bit -=  7;
                        color_bit *= -1;
                    }

                    var color_num = utils.get_bit(data2, color_bit);
                    color_num <<= 1;
                    color_num |= utils.get_bit(data1, color_bit);

                    const color_address: u16 = if (utils.is_bit_set(attributes, 4)) 0xFF49 else 0xFF48;
                    const color = self.get_color(color_num, color_address);

                    const pixel_x = 7 - tile_pixel;                    
                    const pixel = pos_x + pixel_x;

                    self.screen_data[pixel][scanline][0] = color.red; 
                    self.screen_data[pixel][scanline][1] = color.green; 
                    self.screen_data[pixel][scanline][2] = color.blue; 
                }
            }
        }
    }

    fn get_color(self: Emulator, color_num: u8, address: u16) Color {
        const color_to_return = Color{};
        const palette = self.read_memory(address);
        var hi = 0;
        var lo = 0;

        switch (color_num) {
            0 => {
                hi = 1; lo = 0;
            },
            1 => {
                hi = 3; lo = 2;
            },
            2 => {
                hi = 5; lo = 4;
            },
            3 => {
                hi = 7; lo = 6;
            }
        }

        var color = utils.get_bit(palette, hi) << 1;
        color |= utils.get_bit(palette, lo);

        switch (color) {
            0 => {
                color_to_return = Color{ .red = 255, .green = 255, .blue = 255};
            },
            1 => {
                color_to_return = Color{ .red = 0xCC, .green = 0xCC, .blue = 0xCC};
            },
            2 => {
                color_to_return = Color{ .red = 0x77, .green = 0x77, .blue = 0x77};
            }
        }

        return color_to_return;
    }

    fn dma_transfer(self: *Emulator, data: u8) void {
        const address: u16 = data << 8;
        for (0x00..0x9F) |i| {
            self.write_memory(0xFE00 + i, self.read_memory(address + i));
        }
    }

    fn read_memory(self: Emulator, address: u16) u8 {
        switch (address) {
            // mapping of the current bank used by the gameboy
            // to the actual memory bank in the cartridge
            0x4000...0x7FFF => {
                const new_address = address - 0x4000;
                return self.cartridge_memory[new_address + (self.current_rom_bank * 0x4000)];
            },
            // in the case of RAM we offset by 0x2000 bytes because that is
            // the size of single bank
            0xA000...0xBFFF => {
                const new_address = address - 0xA000;
                return self.cartridge_memory[new_address + (self.current_ram_bank * 0x2000)];
            },
            else => {
                return self.memory[address];
            }
        }
    }

    fn handle_banking(self: *Emulator, address: u16, data: u8) void {
        switch (address) {
            0x0000...0x1FFF => {
                if (self.memory_bank_type.is_none()) {
                    return;
                }

                self.enable_ram_bank(address, data);
            },
            0x2000...0x3FFF => {
                if (self.memory_bank_type.is_none()) {
                    return;
                }

                // change lo rom bank
                self.change_lo_rom_bank(data);
            },
            0x4000...0x5FFF => {
                if (self.memory_bank_type.is_MBC1() == false) {
                    return;
                }

                if (self.rom_banking) {
                    self.change_hi_rom_bank(data);
                } else {
                    self.change_ram_bank(data);
                }

            },
            0x6000...0x7FFF => {
                if (self.memory_bank_type.is_MBC1() == false) {
                    return;
                }
                // change rom/ram mode
                self.switch_rom_ram_mode(data);
            },
            else => {
                return;
            },
        }
    }

    fn enable_ram_bank(self: *Emulator, address: u16, data: u8) void {
        if (self.memory_bank_type.is_MBC2()) {
            const byte_to_check = self.memory[address];
            if (utils.is_bit_set(byte_to_check, 4) == false) {
                return;
            }
        }

        const test_data = data & 0xF;
        if (test_data == 0xA) {
            self.enable_ram = true;
        }
        else if (test_data == 0x0) {
            self.enable_ram = false;
        }
    }

    fn change_lo_rom_bank(self: *Emulator, data: u8) void {
        if (self.memory_bank_type.is_MBC2()) {
            self.current_rom_bank = data & 0xF;
            if (self.current_rom_bank == 0) {
                self.current_rom_bank += 1;
            }
            return;
        }

        const lower5_bits = data & 31;
        self.current_rom_bank &= 224;
        self.current_rom_bank |= lower5_bits;
        if (self.current_rom_bank == 0) {
            self.current_rom_bank += 1;
        }
    }

    fn change_hi_rom_bank(self: *Emulator, data: u8) void {
        // turn off upper 3 bits of current rom bank
        self.current_rom_bank &= 31;

        // turn off the lower 5 bits of the data
        data &= 224;
        self.current_rom_bank |= data;
        if (self.current_rom_bank == 0) {
            self.current_rom_bank += 1;
        }
    }

    fn change_ram_bank(self: *Emulator, data: u8) void {
        // sets the current ram bank based on the lower 2 bits of data
        self.current_ram_bank = data & 0x3;
    }

    fn switch_rom_ram_mode(self: *Emulator, data: u8) void {
        const new_data = data & 0x1;
        self.rom_banking = (new_data == 0);

        if (self.rom_banking) {
            self.current_ram_bank = 0;
        }
    }

    fn read_memory_banking_type(self: Emulator) void {
        switch (self.cartridge_memory[0x147]) {
            1...3 => {
                self.memory_bank_type = .MBC1;
            },
            5, 6 => {
                self.memory_bank_type = .MBC2;
            },
        }
    }

    fn update_graphics(self: *Emulator, cycles: u8) void {
        self.set_lcd_status();

        if (self.is_lcd_enabled() == false) {
            return;
        }

        self.scanline_counter -= cycles;

        if (self.scanline_counter <= 0) {
            self.memory[0xFF44] += 1;
            const current_line = self.read_memory(0xFF44);

            self.scanline_counter = 456;

            if (current_line == 144) {
                self.request_interrupt(0);
            } else if (current_line > 153) {
                self.memory[0xFF44] = 0;
            } else if (current_line < 144) {
                self.draw_scan_line();
            }
        }
    }

    fn set_lcd_status(self: *Emulator) void {
        const status = self.read_memory(0xFF41);
        if (self.is_lcd_enabled() == false) {
            self.scanline_counter = 456;
            self.memory[0xFF44] = 0;
            status &= 252;
            status = utils.set_bit(status, 0);
            self.write_memory(0xFF41, status);
            return;
        }

        const current_line = self.read_memory(0xFF44);
        const current_mode = status & 0x3;

        var mode = 0;
        var req_int = false;

        if (current_line >= 144) {
            mode = 1;
            status = utils.set_bit(status, 0);
            status = utils.reset_bit(status, 1);
            req_int = utils.is_bit_set(status, 4);
        } else {
            const search_sprites_mode_end = 456 - 80;
            const transfer_data_mode_end = search_sprites_mode_end - 172;

            if (self.scanline_counter >= search_sprites_mode_end) {
                mode = 2;
                status = utils.set_bit(status, 1);
                status = utils.reset_bit(status, 0);
                req_int = utils.is_bit_set(status, 5);
            } else if (self.scanline_counter >= transfer_data_mode_end) {
                mode = 3;
                status = utils.set_bit(status, 1);
                status = utils.set_bit(status, 0);
            } else {
                mode = 0;
                status = utils.reset_bit(status, 1);
                status = utils.reset_bit(status, 3);
                req_int = utils.is_bit_set(status, 3);
            }
        }

        if (req_int and mode != current_mode) {
            self.request_interrupt(1);
        }

        if (current_line == self.read_memory(0xFF45)) {
            status = utils.set_bit(status, 2);
            if (utils.is_bit_set(status, 6)) {
                self.request_interrupt(1);
            }
        } else{
            status = utils.reset_bit(status, 2);
        }

        self.write_memory(0xFF41, status);
    }

    fn is_lcd_enabled(self: Emulator) bool {
        const lcd_control_register = self.read_memory(0xFF40);
        return utils.is_bit_set(lcd_control_register, 7);
    }

    const Color = struct {
        red: u8 = 0,
        green: u8 = 0,
        blue: u8 = 0
    };

    const Flags = enum(u8) {
        FLAG_Z = 7,
        FLAG_N = 6,
        FLAG_H = 5,
        FLAG_C = 4,
    };

    const Time = enum(u16) {
        TIMA = 0xFF05,
        TMA  = 0xFF06,
        TMC  = 0xFF07,

        pub fn get(self: Time) u16 {
            return @intFromEnum(self);
        }
    };

    const MemoryBankType = enum {
        NONE,
        MBC1,
        MBC2,

        pub fn is_none(self: MemoryBankType) bool {
            return self == .None;
        }

        pub fn is_MBC1(self: MemoryBankType) bool {
            return self == .MBC1;
        }

        pub fn is_MBC2(self: MemoryBankType) bool {
            return self == .MBC2;
        }
    };
};


pub fn main() !void {
    const cartridge_file = try std.fs.cwd().openFile("./src/tetris.gb", .{});
    defer cartridge_file.close();

    var cartridge_memory: [0x200000]u8 = undefined;
    const bytes_read = try cartridge_file.readAll(&cartridge_memory);

    std.debug.print("Bytes read: {}\n", .{bytes_read});

    var reg: Register = Register{ .reg = 0xAABB };
    std.debug.print("Register value: {x}\n", .{reg.reg});
    std.debug.print("Lo value: {x}\n", .{reg.lo().*});
    std.debug.print("Hi value: {x}\n", .{reg.hi().*});

    const some_data = 0b01011001;
    const lower5: u8 = some_data & 31;
    std.debug.print("Lower 5 bits: {}\n", .{lower5});
}
