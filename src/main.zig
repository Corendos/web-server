const std = @import("std");
const builtin = @import("builtin");
const ip = @import("ip.zig");
const Server = @import("server.zig");
const EPollInteractor = @import("epoll_interactor.zig");

var running: bool = true;

fn sigintHandler(sig: c_int) callconv(.C) void {
    _ = sig;
    running = false;
}

fn installSignalHandlers() !void {
    const result = std.os.linux.sigaction(std.os.linux.SIG.INT, &std.os.linux.Sigaction{
        .handler = .{
            .handler = sigintHandler,
        },
        .mask = std.os.linux.empty_sigset,
        .flags = 0,
    }, null);

    if (std.os.linux.getErrno(result) != std.os.linux.E.SUCCESS) return error.SignalInstallFailure;
}

const SERVER_CONFIG = Server.Config{
    .address = ip.IPV4Address.fromString("127.0.0.1"),
    .port = 8888,
};

pub fn main() anyerror!void {
    try installSignalHandlers();
    var server = try Server.create(SERVER_CONFIG);
    defer server.deinit();

    try server.run();
}
