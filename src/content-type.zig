base: ContentBase,
parameter: ?CharSet = null,

pub const default: ContentType = .{ .base = .{ .text = .html } };

pub const ContentType = @This();

pub const ContentBase = union(Base) {
    application: Application,
    audio: Audio,
    font: Font,
    image: Image,
    text: Text,
    video: Video,
    /// Multipart types
    multipart: MultiPart,
    message: MultiPart,

    pub fn string(comptime cb: ContentBase) [:0]const u8 {
        return switch (cb) {
            inline else => |tag| @tagName(cb) ++ "/" ++ @tagName(tag),
        };
    }
};

pub const Base = enum {
    // Basic types
    application,
    audio,
    font,
    image,
    text,
    video,
    /// Multipart types
    multipart,
    message,

    pub fn isMultipart(b: Base) bool {
        return switch (b) {
            .multipart, .message => true,
            else => false,
        };
    }
};

pub const Application = enum {
    @"x-www-form-urlencoded",
    @"x-git-upload-pack-request",
    @"octet-stream",

    pub fn string(comptime app: Application) [:0]const u8 {
        return switch (app) {
            inline else => |r| @typeName(@This())[13..] ++ "/" ++ @tagName(r),
        };
    }

    test "Application.string" {
        // This should be a lowercase A, but I don't know how much time to
        // invest into this yet.
        try std.testing.expectEqualStrings(
            "Application/octet-stream",
            Application.@"octet-stream".string(),
        );
    }
};

pub const Audio = enum {
    ogg,
};

pub const Font = enum {
    otf,
    ttf,
    woff,
};

pub const Image = enum {
    png,
    jpeg,
};

pub const Text = enum {
    plain,
    css,
    html,
    javascript,
};

pub const Video = enum {
    mp4,
};

pub const MultiPart = enum {
    mixed,
    @"form-data",
};

pub const CharSet = enum {
    @"utf-8",
};

pub fn string(comptime ct: ContentType) []const u8 {
    const kind: [:0]const u8 = switch (ct.base) {
        inline else => |tag| @tagName(ct.base) ++ "/" ++ @tagName(tag),
    };

    if (ct.parameter) |param| {
        return switch (param) {
            inline else => |p| return kind ++ "; charset=" ++ @tagName(p),
        };
    } else return kind;
}

test string {
    try std.testing.expectEqualStrings("text/html", default.string());
    try std.testing.expectEqualStrings("image/png", (ContentType{ .base = .{ .image = .png } }).string());

    try std.testing.expectEqualStrings(
        "text/html; charset=utf-8",
        (ContentType{
            .base = .{ .text = .html },
            .parameter = .@"utf-8",
        }).string(),
    );
}

pub fn fromStr(str: []const u8) !ContentType {
    inline for (std.meta.fields(ContentBase)) |field| {
        if (startsWith(u8, str, field.name)) {
            return wrap(field.type, str[field.name.len + 1 ..]);
        }
    }
    return error.UnknownContentType;
}

fn subWrap(comptime Kind: type, str: []const u8) !Kind {
    inline for (std.meta.fields(Kind)) |field| {
        if (startsWith(u8, str, field.name)) {
            return @enumFromInt(field.value);
        }
    }
    return error.UnknownContentType;
}

fn wrap(comptime kind: type, val: anytype) !ContentType {
    return .{
        .base = switch (kind) {
            MultiPart => .{ .multipart = try subWrap(kind, val) },
            Application => .{ .application = try subWrap(kind, val) },
            Audio => .{ .audio = try subWrap(kind, val) },
            Font => .{ .font = try subWrap(kind, val) },
            Image => .{ .image = try subWrap(kind, val) },
            Text => .{ .text = try subWrap(kind, val) },
            Video => .{ .video = try subWrap(kind, val) },
            else => @compileError("not implemented type " ++ @typeName(kind)),
        },
    };
}

test ContentType {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
pub const startsWith = std.mem.startsWith;