const std = @import("std");

pub const SpecialFolder = enum {
    home,
    documents,
    pictures,
    music,
    videos,
    templates,
    desktop,
    downloads,
    public,
    fonts,
    app_menu,
    cache,
    roaming_configuration,
    local_configuration,
    data,
    system_folder,
    runtime,
};

// Explicitly define possible errors to make it clearer what callers need to handle
// TODO: fill this in
pub const Error = error{OutOfMemory};

/// Returns a directory handle, or, if the folder does not exist, `null`.
pub fn open(allocator: *std.mem.Allocator, folder: SpecialFolder, args: std.fs.Dir.OpenDirOptions) (std.fs.Dir.OpenError || Error)!?std.fs.Dir {
    var path_or_null = try getPath(allocator, folder);
    if (path_or_null) |path| {
        defer allocator.free(path);

        return try std.fs.cwd().openDir(path, args);
    } else {
        return null;
    }
}

/// Returns the path to the folder or, if the folder does not exist, `null`.
pub fn getPath(allocator: *std.mem.Allocator, folder: SpecialFolder) Error!?[]const u8 {

    // used for temporary allocations
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    switch (std.builtin.os.tag) {
        .windows => {
            const folder_spec = windows_folder_spec.get(folder);

            switch (folder_spec) {
                .by_guid => |guid| {
                    var dir_path_ptr: [*:0]u16 = undefined;
                    switch (std.os.windows.shell32.SHGetKnownFolderPath(
                        &guid,
                        std.os.windows.KF_FLAG_CREATE, // TODO: Chose sane option here?
                        null,
                        &dir_path_ptr,
                    )) {
                        std.os.windows.S_OK => {
                            defer std.os.windows.ole32.CoTaskMemFree(@ptrCast(*c_void, dir_path_ptr));
                            const global_dir = std.unicode.utf16leToUtf8Alloc(allocator, std.mem.spanZ(dir_path_ptr)) catch |err| switch (err) {
                                error.UnexpectedSecondSurrogateHalf => return null,
                                error.ExpectedSecondSurrogateHalf => return null,
                                error.DanglingSurrogateHalf => return null,
                                error.OutOfMemory => return error.OutOfMemory,
                            };
                            return global_dir;
                        },
                        std.os.windows.E_OUTOFMEMORY => return error.OutOfMemory,
                        else => return null,
                    }
                },
                .by_env => |env_path| {
                    if (env_path.subdir) |sub_dir| {
                        const root_path = std.process.getEnvVarOwned(&arena.allocator, env_path.env_var) catch |err| switch (err) {
                            error.EnvironmentVariableNotFound => return null,
                            error.InvalidUtf8 => return null,
                            error.OutOfMemory => |e| return e,
                        };
                        return try std.fs.path.join(allocator, &[_][]const u8{ root_path, sub_dir });
                    } else {
                        return std.process.getEnvVarOwned(allocator, env_path.env_var) catch |err| switch (err) {
                            error.EnvironmentVariableNotFound => return null,
                            error.InvalidUtf8 => return null,
                            error.OutOfMemory => |e| return e,
                        };
                    }
                },
            }
        },
        .macosx => {
            // TODO: Implement
            @panic("not implemented yet");
        },

        // Assume unix derivatives with XDG
        else => {
            // TODO: Implement
            @panic("not implemented yet");
        },
    }
    unreachable;
}

/// Contains the GUIDs for each available known-folder on windows
const WindowsFolderSpec = union(enum) {
    by_guid: std.os.windows.GUID,
    by_env: struct {
        env_var: []const u8,
        subdir: ?[]const u8,
    },
};

/// Contains the xdg environment variable amd the default value for each available known-folder on windows
const XdgFolderSpec = struct {
    env: ?struct {
        name: []const u8,
        suffix: ?[]const u8,
    },
    default: ?struct {
        path: []const u8,
        inside_home: bool,
    },
};

/// This returns a struct type with one field per SpecialFolder of type `T`.
/// used for storing different config data per field
fn SpecialFolderConfig(comptime T: type) type {
    return struct {
        const Self = @This();

        home: T,
        documents: T,
        pictures: T,
        music: T,
        videos: T,
        templates: T,
        desktop: T,
        downloads: T,
        public: T,
        fonts: T,
        app_menu: T,
        cache: T,
        roaming_configuration: T,
        local_configuration: T,
        data: T,
        system_folder: T,
        runtime: T,

        fn get(self: Self, folder: SpecialFolder) T {
            inline for (std.meta.fields(Self)) |fld| {
                if (folder == @field(SpecialFolder, fld.name))
                    return @field(self, fld.name);
            }
            unreachable;
        }
    };
}

/// Stores how to find each special folder on windows.
const windows_folder_spec = comptime blk: {
    // workaround for zig eval branch quota when parsing the GUIDs
    @setEvalBranchQuota(10_000);
    break :blk SpecialFolderConfig(WindowsFolderSpec){
        .home = WindowsFolderSpec{ .by_guid = std.os.windows.GUID.parse("{5E6C858F-0E22-4760-9AFE-EA3317B67173}") }, // FOLDERID_Profile
        .documents = WindowsFolderSpec{ .by_guid = std.os.windows.GUID.parse("{FDD39AD0-238F-46AF-ADB4-6C85480369C7}") }, // FOLDERID_Documents
        .pictures = WindowsFolderSpec{ .by_guid = std.os.windows.GUID.parse("{33E28130-4E1E-4676-835A-98395C3BC3BB}") }, // FOLDERID_Pictures
        .music = WindowsFolderSpec{ .by_guid = std.os.windows.GUID.parse("{4BD8D571-6D19-48D3-BE97-422220080E43}") }, // FOLDERID_Music
        .videos = WindowsFolderSpec{ .by_guid = std.os.windows.GUID.parse("{18989B1D-99B5-455B-841C-AB7C74E4DDFC}") }, // FOLDERID_Videos
        .templates = WindowsFolderSpec{ .by_guid = std.os.windows.GUID.parse("{A63293E8-664E-48DB-A079-DF759E0509F7}") }, // FOLDERID_Templates
        .desktop = WindowsFolderSpec{ .by_guid = std.os.windows.GUID.parse("{B4BFCC3A-DB2C-424C-B029-7FE99A87C641}") }, // FOLDERID_Desktop
        .downloads = WindowsFolderSpec{ .by_guid = std.os.windows.GUID.parse("{374DE290-123F-4565-9164-39C4925E467B}") }, // FOLDERID_Downloads
        .public = WindowsFolderSpec{ .by_guid = std.os.windows.GUID.parse("{DFDF76A2-C82A-4D63-906A-5644AC457385}") }, // FOLDERID_Public
        .fonts = WindowsFolderSpec{ .by_guid = std.os.windows.GUID.parse("{FD228CB7-AE11-4AE3-864C-16F3910AB8FE}") }, // FOLDERID_Fonts
        .app_menu = WindowsFolderSpec{ .by_guid = std.os.windows.GUID.parse("{625B53C3-AB48-4EC1-BA1F-A1EF4146FC19}") }, // FOLDERID_StartMenu
        .cache = WindowsFolderSpec{ .by_env = .{ .env_var = "LOCALAPPDATA", .subdir = "Temp" } }, // %LOCALAPPDATA%\Temp
        .roaming_configuration = WindowsFolderSpec{ .by_env = .{ .env_var = "APPDATA", .subdir = null } }, // %APPDATA%
        .local_configuration = WindowsFolderSpec{ .by_guid = std.os.windows.GUID.parse("{F1B32785-6FBA-4FCF-9D55-7B8E7F157091}") }, // FOLDERID_LocalAppData
        .data = WindowsFolderSpec{ .by_env = .{ .env_var = "APPDATA", .subdir = null } }, // %LOCALAPPDATA%\Temp
        .system_folder = WindowsFolderSpec{ .by_guid = std.os.windows.GUID.parse("{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}") }, // FOLDERID_System
        .runtime = WindowsFolderSpec{ .by_env = .{ .env_var = "LOCALAPPDATA", .subdir = "Temp" } },
    };
};

/// Stores how to find each special folder in xdg.
const xdg_folder_spec = comptime blk: {
    // workaround for zig eval branch quota when parsing the GUIDs
    @setEvalBranchQuota(10_000);
    break :blk SpecialFolderConfig(XdgFolderSpec){
        .home = XdgFolderSpec{ .env = .{ .name = "HOME", .suffix = null }, .default = null },
        .documents = XdgFolderSpec{ .env = .{ .name = "XDG_DOCUMENTS_DIR", .suffix = null }, .default = .{ .path = "Documents", .inside_home = true } },
        .pictures = XdgFolderSpec{ .env = .{ .name = "XDG_PICTURES_DIR", .suffix = null }, .default = .{ .path = "Pictures", .inside_home = true } },
        .music = XdgFolderSpec{ .env = .{ .name = "XDG_MUSIC_DIR", .suffix = null }, .default = .{ .path = "Music", .inside_home = true } },
        .videos = XdgFolderSpec{ .env = .{ .name = "XDG_VIDEOS_DIR", .suffix = null }, .default = .{ .path = "Videos", .inside_home = true } },
        .templates = XdgFolderSpec{ .env = .{ .name = "XDG_TEMPLATES_DIR", .suffix = null }, .default = .{ .path = "Templates", .inside_home = true } },
        .desktop = XdgFolderSpec{ .env = .{ .name = "XDG_DESKTOP_DIR", .suffix = null }, .default = .{ .path = "Desktop", .inside_home = true } },
        .downloads = XdgFolderSpec{ .env = .{ .name = "XDG_DOWNLOAD_DIR", .suffix = null }, .default = .{ .path = "Downloads", .inside_home = true } },
        .public = XdgFolderSpec{ .env = .{ .name = "XDG_PUBLICSHARE_DIR", .suffix = null }, .default = .{ .path = "Public", .inside_home = true } },
        .fonts = XdgFolderSpec{ .env = .{ .name = "XDG_DATA_HOME", .suffix = "fonts" }, .default = .{ .path = ".local/share/fonts", .inside_home = true } },
        .app_menu = XdgFolderSpec{ .env = .{ .name = "XDG_DATA_HOME", .suffix = "applications" }, .default = .{ .path = ".local/share/applications", .inside_home = true } },
        .cache = XdgFolderSpec{ .env = .{ .name = "XDG_CACHE_HOME", .suffix = null }, .default = .{ .path = ".cache", .inside_home = true } },
        .roaming_configuration = XdgFolderSpec{ .env = .{ .name = "XDG_CONFIG_HOME", .suffix = null }, .default = .{ .path = ".config", .inside_home = true } },
        .local_configuration = XdgFolderSpec{ .env = .{ .name = "XDG_CONFIG_HOME", .suffix = null }, .default = .{ .path = ".config", .inside_home = true } },
        .data = XdgFolderSpec{ .env = .{ .name = "XDG_DATA_HOME", .suffix = null }, .default = .{ .path = ".local/share", .inside_home = true } },
        .system_folder = XdgFolderSpec{ .env = null, .default = .{ .path = "/", .inside_home = false } },
        .runtime = XdgFolderSpec{ .env = .{ .name = "XDG_RUNTIME_DIR", .suffix = null }, .default = null },
    };
};

// Ref decls
comptime {
    _ = SpecialFolder;
    _ = Error;
    _ = open;
    _ = getPath;
}

test "query each known folders" {
    inline for (std.meta.fields(SpecialFolder)) |fld| {
        var path_or_null = try getPath(std.testing.allocator, @field(SpecialFolder, fld.name));
        if (path_or_null) |path| {
            // TODO: Remove later
            std.debug.warn("{} => '{}'\n", .{ fld.name, path });
            std.testing.allocator.free(path);
        }
    }
}

test "open each known folders" {
    inline for (std.meta.fields(SpecialFolder)) |fld| {
        var dir_or_null = try open(std.testing.allocator, @field(SpecialFolder, fld.name), .{ .iterate = false, .access_sub_paths = true });
        if (dir_or_null) |*dir| {
            dir.close();
        }
    }
}

test "query each xdg known folders" {
    // TODO: Implement this test
    _ = xdg_folder_spec;
}
