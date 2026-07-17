const std = @import("std");
const Build = std.Build;
const ResolvedTarget = Build.ResolvedTarget;
const OptimizeMode = std.builtin.OptimizeMode;

pub fn build(b: *std.Build) void {
    _ = b;
}

pub fn getEmsdkPathFromEnv(b: *Build) []const u8 {
    if (b.graph.environ_map.get("EMSDK")) |path| {
        return path;
    } else {
        @panic("To get the path to emsdk, the EMSDK environment variable must exist!");
    }
}

pub fn getEmccName(target: ResolvedTarget) []const u8 {
    return if (target.result.os.tag == .windows) "emcc.exe" else "emcc";
}

pub fn getEmrunName(target: ResolvedTarget) []const u8 {
    return if (target.result.os.tag == .windows) "emrun.exe" else "emrun";
}

pub fn getIncludePath(b: *Build, emsdk_path: []const u8) []const u8 {
    return b.pathJoin(&.{ emsdk_path, "upstream", "emscripten", "cache", "sysroot", "include" });
}

pub fn getPathToEmcc(b: *Build, target: ResolvedTarget, emsdk_path: []const u8) []const u8 {
    return b.pathJoin(&.{ emsdk_path, "upstream", "emscripten", getEmccName(target) });
}

pub fn getPathToEmrun(b: *Build, target: ResolvedTarget, emsdk_path: []const u8) []const u8 {
    return b.pathJoin(&.{ emsdk_path, "upstream", "emscripten", getEmrunName(target) });
}

pub const EmccLinkOptions = struct {
    target: ResolvedTarget,
    optimize: OptimizeMode,
    name: []const u8,
    lib_main: *Build.Step.Compile, // the actual Zig code must be compiled to a static link library
    emcc_path: []const u8,
    release_use_closure: bool = true,
    release_use_lto: bool = true,
    use_webgpu: bool = false,
    use_webgl2: bool = false,
    use_emmalloc: bool = false,
    use_filesystem: bool = true,
    shell_file_path: ?Build.LazyPath,
    extra_args: []const []const u8 = &.{},
};

pub fn emccLinkStep(b: *Build, options: EmccLinkOptions) !*Build.Step.InstallDir {
    const emcc = b.addSystemCommand(&.{options.emcc_path});
    emcc.setName("emcc"); // hide emcc path
    if (options.optimize == .Debug) {
        emcc.addArgs(&.{ "-Og", "-sSAFE_HEAP=1", "-sSTACK_OVERFLOW_CHECK=1" });
    } else {
        emcc.addArg("-sASSERTIONS=0");
        if (options.optimize == .ReleaseSmall) {
            emcc.addArg("-Oz");
        } else {
            emcc.addArg("-O3");
        }
        if (options.release_use_lto) {
            emcc.addArg("-flto");
        }
        if (options.release_use_closure) {
            emcc.addArgs(&.{ "--closure", "1" });
        }
    }
    if (options.use_webgpu) {
        emcc.addArg("--use-port=emdawnwebgpu");
    }
    if (options.use_webgl2) {
        emcc.addArg("-sUSE_WEBGL2=1");
    }
    if (!options.use_filesystem) {
        emcc.addArg("-sNO_FILESYSTEM=1");
    }
    if (options.use_emmalloc) {
        emcc.addArg("-sMALLOC='emmalloc'");
    }
    if (options.shell_file_path) |shell_file_path| {
        emcc.addPrefixedFileArg("--shell-file=", shell_file_path);
    }
    for (options.extra_args) |arg| {
        emcc.addArg(arg);
    }

    // add the main lib, and then scan for library dependencies and add those too
    emcc.addArtifactArg(options.lib_main);
    for (options.lib_main.getCompileDependencies(false)) |item| {
        if (item.kind == .lib) {
            emcc.addArtifactArg(item);
        }
    }
    emcc.addArg("-o");
    const out_file = emcc.addOutputFileArg(b.fmt("{s}.html", .{options.name}));

    // the emcc linker creates 3 output files (.html, .wasm and .js)
    const install = b.addInstallDirectory(.{
        .source_dir = out_file.dirname(),
        .install_dir = .prefix,
        .install_subdir = "web",
    });
    install.step.dependOn(&emcc.step);
    return install;
}

// build a run step which uses the emsdk emrun command to run a build target in the browser
pub const EmrunOptions = struct {
    name: []const u8,
    emrun_path: []const u8,
};

pub fn emrunStep(b: *Build, options: EmrunOptions) *Build.Step.Run {
    return b.addSystemCommand(&.{ options.emrun_path, b.fmt("{s}/web/{s}.html", .{ b.install_path, options.name }) });
}
