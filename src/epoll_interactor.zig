const std = @import("std");
const linux = std.os.linux;
const EPoll = @import("epoll.zig");

const Self = @This();

pub const Error = error{
    OperationAborted,
    WaitError,
};

pub const EventType = struct {
    pub const Read: u32 = linux.EPOLL.IN;
    pub const Write: u32 = linux.EPOLL.OUT;
    pub const ReadHangUp: u32 = linux.EPOLL.RDHUP;
    pub const ExceptionalCondition: u32 = linux.EPOLL.PRI;
    pub const Error: u32 = linux.EPOLL.ERR;
    pub const HangUp: u32 = linux.EPOLL.HUP;
};

pub const Event = struct {
    flags: u32,
    file_descriptor: i32,
};

epoll_instance: EPoll,
allocator: std.mem.Allocator,
registered_fds: std.AutoHashMap(i32, void),

pub fn init(allocator: std.mem.Allocator) !Self {
    return Self{
        .epoll_instance = try EPoll.create(),
        .allocator = allocator,
        .registered_fds = std.AutoHashMap(i32, void).init(allocator),
    };
}

pub fn deinit(self: *Self) void {
    var it = self.registered_fds.keyIterator();
    while (it.next()) |key| {
        std.log.debug("Closing fd {}", .{key.*});
        const result = std.os.linux.close(key.*);
        const err = std.os.linux.getErrno(result);
        if (err != std.os.linux.E.SUCCESS) {
            std.log.debug("Failed to close fd", .{});
        }
    }

    std.log.debug("Clearing registered fds", .{});
    self.registered_fds.clearAndFree();

    self.epoll_instance.destroy() catch unreachable;
}

pub fn register(self: *Self, fd: i32, events: u32) !void {
    var event = EPoll.Event{
        .events = events,
        .data = EPoll.Data{
            .fd = fd,
        },
    };

    try self.epoll_instance.control(EPoll.ControlOperation.Add, fd, &event);
    try self.registered_fds.put(fd, undefined);
}

pub fn unregister(self: *Self, fd: i32) void {
    if (self.registered_fds.remove(fd)) {
        self.epoll_instance.control(EPoll.ControlOperation.Delete, fd, null) catch unreachable;
    }
}

pub fn waitEvent(self: *Self, comptime count: u32, events: *[count]Event) Error![]Event {
    var epoll_events: [count]linux.epoll_event = undefined;
    return if (self.epoll_instance.wait(epoll_events[0..], null)) |result| {
        for (result) |*e, i| {
            events.*[i] = Event{
                .flags = e.events,
                .file_descriptor = e.data.fd,
            };
        }
        return events.*[0..result.len];
    } else |err| switch (err) {
        EPoll.Error.OperationAborted => error.OperationAborted,
        else => error.WaitError,
    };
}
