const std = @import("std");

pub fn posixErrToAnyErr(err: std.c.E) anyerror {
    return switch (err) {
        .NOENT => error.FileNotFound,
        .ACCES, .PERM => error.AccessDenied,
        .EXIST => error.PathAlreadyExists,
        .ISDIR => error.IsDir,
        .NOTDIR => error.NotDir,
        .MFILE, .NFILE => error.SystemResources,
        .NAMETOOLONG => error.NameTooLong,
        .INTR => error.Interrupted,
        .WOULDBLOCK, .AGAIN => error.WouldBlock,
        .BADF => error.BadFileDescriptor,
        .IO => error.IOError,
        .FAULT => error.BadAddress,
        .BUSY => error.Busy,
        .DEADLK => error.Deadlock,
        .NOMEM => error.OutOfMemory,
        .NOSPC => error.NoSpaceLeft,
        .PIPE => error.BrokenPipe,
        .ROFS => error.ReadOnlyFilesystem,
        .TIMEDOUT => error.TimedOut,
        .INVAL => error.InvalidArgument,
        else => error.Unexpected,
    };
}
