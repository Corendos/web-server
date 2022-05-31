const std = @import("std");
const linux = std.os.linux;

const Self = @This();

pub const Error = error{
    Invalid,
    TooManyFiles,
    NoMemory,
    UnexpectedError,
    BadFileDescriptor,
    AlreadyExist,
    CircularLoop,
    NoEntry,
    NoSpace,
    PermissionDenied,
    Fault,
    OperationAborted,
    IOError,
    QuotaExceeded,
};

pub const ControlOperation = enum(u32) {
    Add = linux.EPOLL.CTL_ADD,
    Modify = linux.EPOLL.CTL_MOD,
    Delete = linux.EPOLL.CTL_DEL,
};

pub const Event = linux.epoll_event;
pub const Data = linux.epoll_data;

fd: i32,

pub fn create() Error!Self {
    const result = linux.epoll_create();
    const err = linux.getErrno(result);
    return switch (err) {
        linux.E.SUCCESS => Self{ .fd = @intCast(i32, result) },
        linux.E.INVAL => error.Invalid,
        linux.E.MFILE, linux.E.NFILE => error.TooManyFiles,
        linux.E.NOMEM => error.NoMemory,
        else => error.UnexpectedError,
    };
}

pub fn control(self: *const Self, op: ControlOperation, file_descriptor: i32, event: ?*Event) !void {
    if (op != ControlOperation.Delete and event == null) @panic("null is allowed only for ControlOperation.Delete");

    const result = linux.epoll_ctl(self.fd, @enumToInt(op), file_descriptor, event);
    const err = linux.getErrno(result);
    return switch (err) {
        linux.E.SUCCESS => .{},
        linux.E.BADF => error.BadFileDescriptor,
        linux.E.EXIST => error.AlreadyExist,
        linux.E.INVAL => error.Invalid,
        linux.E.LOOP => error.CircularLoop,
        linux.E.NOENT => error.NoEntry,
        linux.E.NOSPC => error.NoSpace,
        linux.E.PERM => error.PermissionDenied,
        else => error.UnexpectedError,
    };
}

pub fn wait(self: *const Self, events: []Event, timeout: ?i32) Error![]Event {
    const result = linux.epoll_wait(self.fd, events.ptr, @truncate(u32, events.len), timeout orelse -1);
    const err = linux.getErrno(result);
    return switch (err) {
        linux.E.SUCCESS => events[0..result],
        linux.E.INTR => error.OperationAborted,
        linux.E.BADF => error.BadFileDescriptor,
        linux.E.FAULT => error.Fault,
        linux.E.INVAL => error.Invalid,
        else => error.UnexpectedError,
    };
}

pub fn destroy(self: *const Self) Error!void {
    const result = linux.close(self.fd);
    const err = linux.getErrno(result);
    return switch (err) {
        linux.E.SUCCESS => .{},
        linux.E.BADF => error.BadFileDescriptor,
        linux.E.INTR => error.OperationAborted,
        linux.E.IO => error.IOError,
        linux.E.NOSPC => error.NoSpace,
        linux.E.DQUOT => error.QuotaExceeded,
        else => error.UnexpectedError,
    };
}
