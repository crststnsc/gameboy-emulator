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
    screen_data: [160][144][3]u8,
    memory     : [0x10000]u8,

    pub fn update() void {
        // const max_cycles = 69905;
        // var cycles_this_update = 0;

        // TODO
    }
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
    std.debug.print("Hi value: {x}\n", .{reg.hi_alt().*});
}