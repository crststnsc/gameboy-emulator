const std = @import("std");


const Register = struct {
    reg : u16,
    
    pub fn lo(self: *Register) *u8 {
        return @ptrCast(self);
    }

    pub fn hi(self: *Register) *u8 {
        return @ptrCast(@as(*u8, @ptrFromInt(@intFromPtr(self) + 1)));
    }
};


const Emulator = struct {
    screen_data     : [160][144][3]u8,
    memory          : [0x10000]u8,
    program_counter : u16,

    // The stack pointer is modeled as a register 
    // because some opcodes use the hi and lo bits of the stack pointer
    stack_pointer   : Register,

    // Registers
    register_af     : Register,
    register_bc     : Register,
    register_de     : Register,
    register_hl     : Register,
    
    // Cartridge
    cartridge_memory: [0x200000]u8,

    // Memory banking type used by the game (DEFAULT: NONE)
    memory_bank_type: MemoryBankType = MemoryBankType.NONE,
    current_rom_bank: u8, 

    enable_ram      : bool,

    ram_banks       : [0x8000]u8,
    current_ram_bank: u8,
    
    pub fn update() void {
        // const max_cycles = 69905;
        // var cycles_this_update = 0;

        // TODO
    }

    pub fn init(self: *Emulator) Emulator {
        // when the emulator starts we must set the state of registers,
        // the stack pointer, program counter and some memory registers
        self.program_counter = 0x100;
        self.stack_pointer   = 0xFFFE;

        self.init_memory();
        self.init_registers();

        // read the memory banking from the cartridge
        self.read_memory_banking_type();
        self.current_rom_bank = 1;
        self.current_ram_bank = 0;
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

    fn write_memory(self: *Emulator, address: u16, data: u8) void {
        // don't allow to write to read-only memory
        if (address < 0x8000) {
            self.handle_banking(address, data);
        }

        if (address >= 0xA000 and address < 0xC000) {
            if (self.enable_ram) {
                const new_address: u16 = address - 0xA000;
                self.ram_banks[new_address + (self.current_ram_bank * 0x2000)] = data;
            }
        }

        // restricted memory area
        else if (address >= 0xFEA0 and address < 0xFEFF) {
            // TODO some warning
        }

        // anything written to ECHO also gets written in RAM 
        else if (address >= 0xE000 and address < 0xFE00) {
            self.memory[address] = data;
            self.write_memory(address - 0x2000, data);
        }
        else {
            self.memory[address] = data;
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

                // enable ram bank 
            },
            0x2000...0x3FFF => {
                if (self.memory_bank_type.is_none()) {
                    return;
                }
                    
                // change lo rom bank
            },
            0x4000...0x5FFF => {
                if (self.memory_bank_type.is_MBC1() == false) {
                    return;
                }

                // if rom banking 
                //      change hi rom bank
                // else
                //      change ram bank 
            },
            else => { return; }
        }
    }

    fn read_memory_banking_type(self: Emulator) void {
        switch (self.cartridge_memory[0x147]) {
            1...3 => {
                self.memory_bank_type = .MBC1;
            },
            5, 6  => {
                self.memory_bank_type = .MBC2;
            }
        }
    }

    const Flags = enum(u8) {
        FLAG_Z = 7,
        FLAG_N = 6,
        FLAG_H = 5,
        FLAG_C = 4,
        DEFAULT_FLAG
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
    };
};


pub fn main() !void {
    const cartridge_file = try std.fs.cwd().openFile("./src/tetris.gb", .{});
    defer cartridge_file.close();

    var cartridge_memory: [0x200000]u8 = undefined;
    const bytes_read = try cartridge_file.readAll(&cartridge_memory);

    std.debug.print("Bytes read: {}\n", .{bytes_read});

    var reg: Register = Register {.reg = 0xAABB};
    std.debug.print("Register value: {x}\n", .{reg.reg});
    std.debug.print("Lo value: {x}\n", .{reg.lo().*});
    std.debug.print("Hi value: {x}\n", .{reg.hi().*});

}