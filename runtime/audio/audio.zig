const ma = @cImport({
    @cInclude("audio/miniaudio.h");
});

const Logger = @import("../log.zig").Logger;

pub const AudioPlayer = struct {
    config: ma.ma_decoder_config,
    engine: ma.ma_engine,
    logger: Logger("audio", 1024),

    pub const Sound = struct {
        decoder: ma.ma_decoder,
        sound: ma.ma_sound,
    };

    pub fn init() !AudioPlayer {
        var engine: ma.ma_engine = undefined;
        try tryMaResult(ma.ma_engine_init(null, &engine));
        errdefer ma.ma_engine_uninit(&engine);

        return .{
            .config = ma.ma_decoder_config_init(ma.ma_format_f32, 2, 44100),
            .engine = engine,
            .logger = Logger("audio", 1024).init(),
        };
    }

    pub fn deinit(self: *AudioPlayer) void {
        ma.ma_engine_uninit(&self.engine);
    }

    pub fn loadSound(self: *AudioPlayer, data: []const u8) !Sound {
        var sound: Sound = undefined;

        var result = ma.ma_decoder_init_memory(data.ptr, data.len, &self.config, &sound.decoder);
        try tryMaResult(result);

        result = ma.ma_sound_init_from_data_source(&self.engine, &sound.decoder, 0, null, &sound.sound);
        try tryMaResult(result);

        return sound;
    }

    pub fn unloadSound(self: *AudioPlayer, sound: *Sound) void {
        ma.ma_sound_uninit(&sound.sound);
        const status = ma.ma_decoder_uninit(&sound.decoder);
        tryMaResult(status) catch |err| {
            _ = self.logger.err("failed to uninit decoder: {s}", .{@errorName(err)});
        };
    }
};

fn tryMaResult(result: ma.ma_result) !void {
    return switch (result) {
        ma.MA_SUCCESS => void{},
        ma.MA_ERROR => error.MaError,
        ma.MA_INVALID_ARGS => error.MaInvalidArgs,
        ma.MA_INVALID_OPERATION => error.MaInvalidOperation,
        ma.MA_OUT_OF_MEMORY => error.MaOutOfMemory,
        ma.MA_OUT_OF_RANGE => error.MaOutOfRange,
        ma.MA_ACCESS_DENIED => error.MaAccessDenied,
        ma.MA_DOES_NOT_EXIST => error.MaDoesNotExist,
        ma.MA_ALREADY_EXISTS => error.MaAlreadyExists,
        ma.MA_TOO_MANY_OPEN_FILES => error.MaTooManyOpenFiles,
        ma.MA_INVALID_FILE => error.Mainvalid_file,
        ma.MA_TOO_BIG => error.MaTooBig,
        ma.MA_PATH_TOO_LONG => error.MaPathTooLong,
        ma.MA_NAME_TOO_LONG => error.MaNameTooLong,
        ma.MA_NOT_DIRECTORY => error.MaNotDirectory,
        ma.MA_IS_DIRECTORY => error.MaIsDirectory,
        ma.MA_DIRECTORY_NOT_EMPTY => error.MaDirectoryNotEmpty,
        ma.MA_AT_END => error.MaAtEnd,
        ma.MA_NO_SPACE => error.MaNoSpace,
        ma.MA_BUSY => error.MaBusy,
        ma.MA_IO_ERROR => error.MaIoError,
        ma.MA_INTERRUPT => error.MaInterrupt,
        ma.MA_UNAVAILABLE => error.Maunavailable,
        ma.MA_ALREADY_IN_USE => error.MaAlreadyInUse,
        ma.MA_BAD_ADDRESS => error.MaBadAddress,
        ma.MA_BAD_SEEK => error.MaBadSeek,
        ma.MA_BAD_PIPE => error.MaBadPipe,
        ma.MA_DEADLOCK => error.MaDeadlock,
        ma.MA_TOO_MANY_LINKS => error.MaTooManyLinks,
        ma.MA_NOT_IMPLEMENTED => error.MaNotImplemented,
        ma.MA_NO_MESSAGE => error.MaNoMessage,
        ma.MA_BAD_MESSAGE => error.MaBadMessage,
        ma.MA_NO_DATA_AVAILABLE => error.MaNoDataAvailable,
        ma.MA_INVALID_DATA => error.MaInvalidData,
        ma.MA_TIMEOUT => error.MaTimeout,
        ma.MA_NO_NETWORK => error.MaNoNetwork,
        ma.MA_NOT_UNIQUE => error.MaNotUnique,
        ma.MA_NOT_SOCKET => error.MaNotSocket,
        ma.MA_NO_ADDRESS => error.MaNoAddress,
        ma.MA_BAD_PROTOCOL => error.MaBadProtocol,
        ma.MA_PROTOCOL_UNAVAILABLE => error.MaProtocolUnavailable,
        ma.MA_PROTOCOL_NOT_SUPPORTED => error.MaProtocolNotSupported,
        ma.MA_PROTOCOL_FAMILY_NOT_SUPPORTED => error.MaProtocolFamilyNotSupported,
        ma.MA_ADDRESS_FAMILY_NOT_SUPPORTED => error.MaAddressFamilyNotSupported,
        ma.MA_SOCKET_NOT_SUPPORTED => error.MaSocketNotSupported,
        ma.MA_CONNECTION_RESET => error.MaConnectionReset,
        ma.MA_ALREADY_CONNECTED => error.MaAlreadyConnected,
        ma.MA_NOT_CONNECTED => error.MaNotConnected,
        ma.MA_CONNECTION_REFUSED => error.MaConnectionRefused,
        ma.MA_NO_HOST => error.MaNoHost,
        ma.MA_IN_PROGRESS => error.MaInProgress,
        ma.MA_CANCELLED => error.MaCancelled,
        ma.MA_MEMORY_ALREADY_MAPPED => error.MaMemoryAlreadyMapped,
        ma.MA_CRC_MISMATCH => error.MaCrcMismatch,
        ma.MA_FORMAT_NOT_SUPPORTED => error.MaFormatNotSupported,
        ma.MA_DEVICE_TYPE_NOT_SUPPORTED => error.MaDeviceTypeNotSupported,
        ma.MA_SHARE_MODE_NOT_SUPPORTED => error.MaShareModeNotSupported,
        ma.MA_NO_BACKEND => error.MaNoBackend,
        ma.MA_NO_DEVICE => error.MaNoDevice,
        ma.MA_API_NOT_FOUND => error.MaApiNotFound,
        ma.MA_INVALID_DEVICE_CONFIG => error.MaInvalidDeviceConfig,
        ma.MA_LOOP => error.MaLoop,
        ma.MA_BACKEND_NOT_ENABLED => error.MaBackendNotEnabled,
        ma.MA_DEVICE_NOT_INITIALIZED => error.MaDeviceNotInitialized,
        ma.MA_DEVICE_ALREADY_INITIALIZED => error.MaDeviceAlreadyInitialized,
        ma.MA_DEVICE_NOT_STARTED => error.MaDeviceNotStarted,
        ma.MA_DEVICE_NOT_STOPPED => error.MaDeviceNotStopped,
        ma.MA_FAILED_TO_INIT_BACKEND => error.MaFailedToInitBackend,
        ma.MA_FAILED_TO_OPEN_BACKEND_DEVICE => error.MaFailedToOpenBackendDevice,
        ma.MA_FAILED_TO_START_BACKEND_DEVICE => error.MaFailedToStartBackendDevice,
        ma.MA_FAILED_TO_STOP_BACKEND_DEVICE => error.MaFailedToStopBackendDevice,
        else => error.MaUnknownError,
    };
}
