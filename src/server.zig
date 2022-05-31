const std = @import("std");
const linux = std.os.linux;
const ip = @import("ip.zig");
const net = @import("network.zig");
const EPollInteractor = @import("epoll_interactor.zig");

const Self = @This();

pub const Config = struct {
    address: ip.IPV4Address,
    port: u16,
    backlog: u32 = 32,
};

pub const Error = error{
    SocketCreationFailure,
    SocketSetOptionFailure,
    SocketBindFailure,
    SocketListenFailure,
    AcceptFailure,
    UnsupportedFamily,
};

const Connection = struct {
    address: ip.IPV4Address,
    port: u16,
    fd: i32,

    pub fn format(value: Connection, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try std.fmt.format(writer, "Connection{{ .address = {}, .port = {}, .fd: {} }}", .{
            value.address,
            value.port,
            value.fd,
        });
    }
};

config: Config,
fd: i32,

pub fn create(config: Config) Error!Self {
    const socket_result = std.os.linux.socket(std.os.linux.PF.INET, std.os.linux.SOCK.STREAM, 0);
    if (std.os.linux.getErrno(socket_result) != std.os.linux.E.SUCCESS) {
        return Error.SocketCreationFailure;
    }
    const socket_fd: i32 = @intCast(i32, socket_result);
    errdefer {
        std.log.debug("Closing socket due to failure", .{});
        _ = std.os.linux.close(socket_fd);
    }

    const setopt_result = std.os.linux.setsockopt(socket_fd, std.os.linux.SOL.SOCKET, std.os.linux.SO.REUSEADDR, @ptrCast([*]const u8, &@as(c_int, 1)), @sizeOf(c_int));
    if (std.os.linux.getErrno(setopt_result) != std.os.linux.E.SUCCESS) {
        std.log.debug("Reason: {}", .{std.os.linux.getErrno(setopt_result)});
        return Error.SocketSetOptionFailure;
    }

    const addr = std.os.linux.sockaddr.in{
        .port = net.conversion.hostToNetwork(u16, config.port),
        .addr = net.conversion.hostToNetwork(u32, config.address.value),
    };
    const bind_result = std.os.linux.bind(socket_fd, @ptrCast(*const std.os.linux.sockaddr, &addr), @sizeOf(std.os.linux.sockaddr.in));
    if (std.os.linux.getErrno(bind_result) != std.os.linux.E.SUCCESS) {
        return Error.SocketCreationFailure;
    }

    const listen_result = std.os.linux.listen(socket_fd, config.backlog);
    if (std.os.linux.getErrno(listen_result) != std.os.linux.E.SUCCESS) {
        return Error.SocketListenFailure;
    }

    std.log.info("Listening on \"{}:{}\"", .{
        config.address,
        config.port,
    });

    return Self{ .config = config, .fd = socket_fd };
}

pub fn deinit(self: *Self) void {
    _ = std.os.linux.close(self.fd);
    self.fd = 0;
}

pub fn accept(self: *const Self) Error!Connection {
    var client_addr: std.os.linux.sockaddr align(4) = undefined;
    var client_addr_len: std.os.linux.socklen_t = @sizeOf(std.os.linux.sockaddr);
    const accept_result = std.os.linux.accept(self.fd, &client_addr, &client_addr_len);
    if (std.os.linux.getErrno(accept_result) != std.os.linux.E.SUCCESS) {
        return Error.AcceptFailure;
    }

    if (client_addr.family != std.os.linux.AF.INET) {
        return Error.UnsupportedFamily;
    }

    const inet_client_addr = @ptrCast(*const std.os.linux.sockaddr.in, &client_addr);
    return Connection{
        .address = ip.IPV4Address{ .value = net.conversion.networkToHost(u32, inet_client_addr.addr) },
        .port = net.conversion.networkToHost(u16, inet_client_addr.port),
        .fd = @intCast(i32, accept_result),
    };
}

pub fn run(self: *Self) !void {
    _ = self;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var interactor = try EPollInteractor.init(gpa.allocator());
    defer interactor.deinit();

    try interactor.register(self.fd, std.os.linux.EPOLL.IN);

    var events: [16]EPollInteractor.Event = undefined;
    while (true) {
        const in_events = interactor.waitEvent(events.len, &events) catch |err| switch (err) {
            EPollInteractor.Error.OperationAborted => break,
            else => continue,
        };

        for (in_events) |*event| {
            if (event.file_descriptor == self.fd) {
                const connection = self.accept() catch continue;
                std.log.debug("New connection: {}", .{connection});

                try interactor.register(connection.fd, std.os.linux.EPOLL.IN);
            } else {
                if (event.flags & EPollInteractor.EventType.Read != 0) {
                    var buffer: [256]u8 = undefined;
                    const read_result = std.os.linux.read(event.file_descriptor, &buffer, buffer.len);
                    const read_error = std.os.linux.getErrno(read_result);
                    if (read_error != std.os.linux.E.SUCCESS) {
                        std.log.debug("Failed to read from fd {}", .{event.file_descriptor});
                        continue;
                    } else {
                        if (read_result == 0) {
                            std.log.debug("fd {} closed", .{event.file_descriptor});
                            interactor.unregister(event.file_descriptor);
                            _ = std.os.linux.close(event.file_descriptor);
                        } else {
                            std.log.debug("Received from fd {}: {s}", .{ event.file_descriptor, buffer[0..read_result] });
                        }
                    }
                }
            }
        }
    }
}

//fn handleNewConnection(self: *Self, event: )