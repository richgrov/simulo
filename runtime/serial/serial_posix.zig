const std = @import("std");

const c = @cImport({
    @cInclude("termios.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
});

fn flag_cast(i: c_int) c.tcflag_t {
    return @intCast(@as(c_uint, @bitCast(i)));
}

pub const Serial = struct {
    fd: c_int,

    pub fn open(port_path: [:0]const u8, timeout_ms: u32) !Serial {
        const fd = c.open(port_path, c.O_RDWR | c.O_NOCTTY | c.O_SYNC);
        if (fd < 0) return error.OpenFailed;
        errdefer _ = c.close(fd);

        var tio: c.struct_termios = undefined;
        if (c.tcgetattr(fd, &tio) != 0) return error.ConfigReadFailed;

        c.cfmakeraw(&tio);

        _ = c.cfsetispeed(&tio, c.B115200);
        _ = c.cfsetospeed(&tio, c.B115200);

        // 8 data bits
        tio.c_cflag &= ~(@as(c_uint, c.CSIZE));
        tio.c_cflag |= c.CS8;
        // No parity
        tio.c_cflag &= flag_cast(~c.PARENB);
        // 1 stop bit
        tio.c_cflag &= flag_cast(~c.CSTOPB);
        // Enable receiver, ignore modem control lines
        tio.c_cflag |= c.CREAD | c.CLOCAL;
        // Disable HW flow control if defined
        tio.c_cflag &= flag_cast(~c.CRTSCTS);

        // Set read timeout: VTIME in deciseconds, VMIN=0 for read-with-timeout semantics
        const ds: u8 = @truncate(if (timeout_ms == 0) 0 else @min((timeout_ms + 99) / 100, 255));
        tio.c_cc[c.VMIN] = 0;
        tio.c_cc[c.VTIME] = ds;

        if (c.tcsetattr(fd, c.TCSANOW, &tio) != 0) return error.ConfigWriteFailed;

        return Serial{ .fd = fd };
    }

    pub fn close(self: *Serial) void {
        if (self.fd >= 0) {
            _ = c.close(self.fd);
            self.fd = -1;
        }
    }

    pub fn writeAll(self: *Serial, bytes: []const u8) !void {
        var offset: usize = 0;
        while (offset < bytes.len) {
            const n = c.write(self.fd, bytes.ptr + offset, bytes.len - offset);
            if (n < 0) return error.WriteFailed;
            offset += @intCast(n);
        }
        _ = c.tcdrain(self.fd);
    }

    pub fn read(self: *Serial, buf: []u8) !usize {
        const n = c.read(self.fd, buf.ptr, buf.len);
        if (n < 0) return error.ReadFailed;
        return @intCast(n);
    }

    pub fn sleepMs(ms: u64) void {
        std.time.sleep(ms * std.time.ns_per_ms);
    }
};
