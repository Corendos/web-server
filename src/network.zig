const std = @import("std");
const builtin = @import("builtin");

pub const conversion = struct {
    pub fn hostToNetwork(comptime T: type, value: T) T {
        if (builtin.cpu.arch.endian() == std.builtin.Endian.Little) {
            return @byteSwap(T, value);
        }
        return value;
    }

    pub fn networkToHost(comptime T: type, value: T) T {
        if (builtin.cpu.arch.endian() == std.builtin.Endian.Little) {
            return @byteSwap(T, value);
        }
        return value;
    }
};
