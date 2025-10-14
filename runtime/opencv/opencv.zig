const opencv = @cImport({
    @cInclude("opencv/opencv.h");
});

const DMat3 = @import("engine").math.DMat3;

pub const c = opencv;

const Logger = @import("../log.zig").Logger;
var logger = Logger("opencv", 512).init();

pub const Mat = struct {
    mat: *opencv.CvMat,

    pub fn init(rows: i32, cols: i32, mat_type: c.CvMatType) !Mat {
        var mat: ?*opencv.CvMat = null;
        const status = opencv.mat_init(&mat, rows, cols, mat_type);
        try tryStatus(status);
        return Mat{
            .mat = mat.?,
        };
    }

    pub fn deinit(self: *Mat) void {
        const status = opencv.mat_release(self.mat);
        tryStatus(status) catch |err| {
            logger.err("failed to release OpenCV mat: {s}", .{@errorName(err)});
        };
    }

    pub fn write(self: *Mat, path: [:0]const u8) !void {
        const status = opencv.mat_write(self.mat, path.ptr);
        try tryStatus(status);
    }

    pub fn decodeFrom(self: *Mat, bytes: []const u8, flags: opencv.CvImreadFlags) void {
        opencv.mat_decode(self.mat, bytes.ptr, @intCast(bytes.len), flags);
    }

    pub fn data(self: *Mat) [*c]u8 {
        return opencv.mat_data(self.mat);
    }

    pub fn convert(self: *Mat, to: opencv.CvConvert, out: *Mat) !void {
        const status = opencv.mat_convert(out.mat, self.mat, to);
        try tryStatus(status);
    }

    pub fn copyTo(self: *Mat, other: *Mat) !void {
        const status = opencv.mat_copy(other.mat, self.mat);
        try tryStatus(status);
    }

    pub fn subtract(self: *Mat, other: *Mat, dest: *Mat) !void {
        const status = opencv.mat_sub(dest.mat, self.mat, other.mat);
        try tryStatus(status);
    }

    //pub fn wrap(self: *Mat, data: [*]u8, rows: i32, cols: i32, mat_type: opencv.CvMatType) !void {
    //    const status = opencv.mat_wrap(self.mat, data, rows, cols, mat_type);
    //    try tryStatus(status);
    //}

    pub fn findChessboardTransform(
        self: *Mat,
        pattern_width: i32,
        pattern_height: i32,
        flags: opencv.CvCalibChessboardFlags,
    ) !?DMat3 {
        var transform: [9]f64 = undefined;
        var found: bool = undefined;
        const status = opencv.find_chessboard_transform(self.mat, pattern_width, pattern_height, flags, &transform, &found);
        try tryStatus(status);
        if (!found) {
            return null;
        }
        return DMat3.fromRowMajorPtr(&transform);
    }

    fn tryStatus(status: opencv.CvStatus) !void {
        switch (status) {
            opencv.StatOk => {},
            opencv.StatUnknownException => return error.CvUnknownException,
            opencv.StatStdException => return error.CvStdException,
            opencv.StatBackTrace => return error.CvBackTrace,
            opencv.StatError => return error.CvError,
            opencv.StatInternal => return error.CvInternalError,
            opencv.StatNoMem => return error.CvNoMem,
            opencv.StatBadArg => return error.CvBadArg,
            opencv.StatBadFunc => return error.CvBadFunc,
            opencv.StatNoConv => return error.CvNoConv,
            opencv.StatAutoTrace => return error.CvAutoTrace,
            opencv.StatHeaderIsNull => return error.CvHeaderIsNull,
            opencv.StatBadImageSize => return error.CvBadImageSize,
            opencv.StatBadOffset => return error.CvBadOffset,
            opencv.StatBadDataPtr => return error.CvBadDataPtr,
            opencv.StatBadStep => return error.CvBadStep,
            opencv.StatBadModelOrChSeq => return error.CvBadModelOrChSeq,
            opencv.StatBadNumChannels => return error.CvBadNumChannels,
            opencv.StatBadNumChannel1U => return error.CvBadNumChannel1U,
            opencv.StatBadDepth => return error.CvBadDepth,
            opencv.StatBadAlphaChannel => return error.CvBadAlphaChannel,
            opencv.StatBadOrder => return error.CvBadOrder,
            opencv.StatBadOrigin => return error.CvBadOrigin,
            opencv.StatBadAlign => return error.CvBadAlign,
            opencv.StatBadCallBack => return error.CvBadCallBack,
            opencv.StatBadTileSize => return error.CvBadTileSize,
            opencv.StatBadCOI => return error.CvBadCOI,
            opencv.StatBadROISize => return error.CvBadROISize,
            opencv.StatMaskIsTiled => return error.CvMaskIsTiled,
            opencv.StatNullPtr => return error.CvNullPtr,
            opencv.StatVecLengthErr => return error.CvVecLengthErr,
            opencv.StatFilterStructContentErr => return error.CvFilterStructContentErr,
            opencv.StatKernelStructContentErr => return error.CvKernelStructContentErr,
            opencv.StatFilterOffsetErr => return error.CvFilterOffsetErr,
            opencv.StatBadSize => return error.CvBadSize,
            opencv.StatDivByZero => return error.CvDivByZero,
            opencv.StatInplaceNotSupported => return error.CvInplaceNotSupported,
            opencv.StatObjectNotFound => return error.CvObjectNotFound,
            opencv.StatUnmatchedFormats => return error.CvUnmatchedFormats,
            opencv.StatBadFlag => return error.CvBadFlag,
            opencv.StatBadPoint => return error.CvBadPoint,
            opencv.StatBadMask => return error.CvBadMask,
            opencv.StatUnmatchedSizes => return error.CvUnmatchedSizes,
            opencv.StatUnsupportedFormat => return error.CvUnsupportedFormat,
            opencv.StatOutOfRange => return error.CvOutOfRange,
            opencv.StatParseError => return error.CvParseError,
            opencv.StatNotImplemented => return error.CvNotImplemented,
            opencv.StatBadMemBlock => return error.CvBadMemBlock,
            opencv.StatAssert => return error.CvAssert,
            opencv.StatGpuNotSupported => return error.CvGpuNotSupported,
            opencv.StatGpuApiCallError => return error.CvGpuApiCallError,
            opencv.StatOpenGlNotSupported => return error.CvOpenGlNotSupported,
            opencv.StatOpenGlApiCallError => return error.CvOpenGlApiCallError,
            opencv.StatOpenCLApiCallError => return error.CvOpenCLApiCallError,
            opencv.StatOpenCLDoubleNotSupported => return error.CvOpenCLDoubleNotSupported,
            opencv.StatOpenCLInitError => return error.CvOpenCLInitError,
            opencv.StatOpenCLNoAMDBlasFft => return error.CvOpenCLNoAMDBlasFft,
            else => {
                logger.err("unknown OpenCV status: {d}", .{status});
                return error.CvUnknownError;
            },
        }
    }
};
