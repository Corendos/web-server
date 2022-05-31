const std = @import("std");
const net = @import("network.zig");

const Parser = struct {
    str: []const u8,
    current_index: u64,

    pub fn init(str: []const u8) Parser {
        return Parser{
            .str = str,
            .current_index = 0,
        };
    }

    pub fn parseU8(self: *Parser) !u8 {
        var value: ?u64 = null;
        while (self.current_index < self.str.len and (self.str[self.current_index] >= '0' and self.str[self.current_index] <= '9')) {
            value = (value orelse 0) * 10 + self.str[self.current_index] - '0';
            self.current_index += 1;
        }

        if (value == null) return error.ParseErrorValueIsNull;
        if (value.? > std.math.maxInt(u8)) return error.ParseErrorValueIsTooBig;
        return @intCast(u8, value.?);
    }

    pub fn parseDot(self: *Parser) !void {
        if (self.current_index < self.str.len and self.str[self.current_index] == '.') {
            self.current_index += 1;
            return;
        }
        return error.ParseError;
    }

    pub fn done(self: *const Parser) bool {
        return self.current_index >= self.str.len;
    }
};

pub const IPV4Address = struct {
    value: u32,

    pub fn fromString(comptime str: []const u8) IPV4Address {
        comptime var parser = Parser.init(str);
        comptime var address = [4]u8{ 0, 0, 0, 0 };
        comptime {
            address[0] = parser.parseU8() catch |err| @compileError(@errorName(err));
            parser.parseDot() catch |err| @compileError(@errorName(err));
            address[1] = parser.parseU8() catch |err| @compileError(@errorName(err));
            parser.parseDot() catch |err| @compileError(@errorName(err));
            address[2] = parser.parseU8() catch |err| @compileError(@errorName(err));
            parser.parseDot() catch |err| @compileError(@errorName(err));
            address[3] = parser.parseU8() catch |err| @compileError(@errorName(err));
            if (!parser.done()) @compileError(@errorName(error.ParseErrorParserNotDone));
        }

        return IPV4Address{
            .value = net.conversion.networkToHost(u32, @bitCast(u32, address)),
        };
    }

    pub fn format(addr: IPV4Address, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        const address_raw = @bitCast([4]u8, addr.value);
        try std.fmt.format(writer, "{}.{}.{}.{}", .{
            address_raw[3],
            address_raw[2],
            address_raw[1],
            address_raw[0],
        });
    }
};