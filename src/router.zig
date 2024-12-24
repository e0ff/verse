routefn: RouteFn,
builderfn: BuilderFn = defaultBuilder,
routerfn: RouterFn = defaultRouter,

/// The default page generator, this is the function that will be called, and
/// expected to write the page data back to the client.
pub const BuildFn = *const fn (*Verse) Error!void;

/// Similar to RouteFn and RouterFn above, Verse requires all page build steps
/// to finish cleanly. While a default is provided. It's strongly recommended
/// that a custom builder function be provided when custom error handling is
/// desired.
pub const BuilderFn = *const fn (*Verse, BuildFn) void;

/// Route Functions are allowed to return errors for select cases where
/// backtracking through the routing system might be useful. This in an
/// exercise left to the caller, as eventually a sever default server error page
/// will need to be returned.
pub const RouteFn = *const fn (*Verse) RoutingError!BuildFn;

/// The provided RouteFn will be wrapped with a default error provider that will
/// return a default BuildFn.
pub const RouterFn = *const fn (*Verse, RouteFn) BuildFn;

/// TODO document
pub const Router = @This();

/// TODO document
pub const UriIter = std.mem.SplitIterator(u8, .scalar);

/// The Verse router will scan through an array of Match structs looking for a
/// given name. Verse doesn't assert that the given name will match a director
/// or endpoint/page specifically. e.g. `/uri/page` and `/uri/page/` will both
/// match to the first identical name, regardless if the matched type is a build
/// function, or a route function.
///
/// A name containing any non alphanumeric char is undefined.
pub const Match = struct {
    /// The name for this resource. Names with length of 0 is valid for
    /// directories.
    name: []const u8,
    /// Map http method to target endpoint.
    methods: Methods,

    /// Separate from the http interface as this is 'internal' to the routing
    /// subsystem, where a single endpoint may respond to multiple http methods.
    pub const Methods = struct {
        CONNECT: ?Target = null,
        DELETE: ?Target = null,
        GET: ?Target = null,
        HEAD: ?Target = null,
        OPTIONS: ?Target = null,
        POST: ?Target = null,
        PUT: ?Target = null,
        TRACE: ?Target = null,
    };

    pub fn target(comptime self: Match, comptime req: Request.Methods) ?Target {
        return switch (req) {
            .CONNECT => self.methods.CONNECT,
            .DELETE => self.methods.DELETE,
            .GET => self.methods.GET,
            .HEAD => self.methods.HEAD,
            .OPTIONS => self.methods.OPTIONS,
            .POST => self.methods.POST,
            .PUT => self.methods.PUT,
            .TRACE => self.methods.TRACE,
        };
    }
};

pub const Target = union(enum) {
    /// An endpoint function that's expected to return the requested page
    /// data.
    build: BuildFn,
    /// A router function that will either
    /// 1) consume the next URI token, and itself call the next routing
    /// function/handler, or
    /// 2) return the build function pointer that will be called directly to
    /// generate the page.
    route: RouteFn,
    /// A Match array for a sub directory, that can be handled by the same
    /// routing function. Provided for convenience.
    simple: []const Match,
};

/// Translation function to convert a tuple of Match objects into
pub fn ROUTER() void {}

/// Default route building helper.
pub fn ROUTE(comptime name: []const u8, comptime match: anytype) Match {
    const target = buildTarget(match);
    return switch (target) {
        .build => |b| ALL(name, b),
        .route, .simple => .{ // TODO only populate if sub target handles method
            .name = name,
            .methods = .{
                .CONNECT = target,
                .DELETE = target,
                .GET = target,
                .HEAD = target,
                .OPTIONS = target,
                .POST = target,
                .PUT = target,
                .TRACE = target,
            },
        },
    };
}

fn buildTarget(comptime match: anytype) Target {
    return switch (@typeInfo(@TypeOf(match))) {
        .Pointer => |ptr| switch (@typeInfo(ptr.child)) {
            .Fn => |fnc| switch (fnc.return_type orelse null) {
                Error!void => .{ .build = match },
                RoutingError!BuildFn => .{ .route = match },
                else => @compileError("unknown function return type" ++ @typeName(ptr.child)),
            },
            else => .{ .simple = match },
        },
        .Fn => |fnc| switch (fnc.return_type orelse null) {
            Error!void => .{ .build = match },
            RoutingError!BuildFn => .{ .route = match },
            else => @compileError("unknown function return type"),
        },
        else => |el| @compileError("match type not supported, for provided type [" ++
            @typeName(@TypeOf(el)) ++
            "]"),
    };
}

/// Defaults to build only for GET, POST, and HEAD, and OPTIONS. Use ALL if your
/// endpoint actually supports every known method.
pub fn ANY(comptime name: []const u8, comptime match: BuildFn) Match {
    const target = buildTarget(match);
    return .{
        .name = name,
        .methods = .{
            .GET = target,
            .POST = target,
            .HEAD = target,
            .OPTIONS = target,
        },
    };
}

pub fn ALL(comptime name: []const u8, comptime match: BuildFn) Match {
    const target = buildTarget(match);
    return .{
        .name = name,
        .methods = .{
            .CONNECT = target,
            .DELETE = target,
            .GET = target,
            .HEAD = target,
            .OPTIONS = target,
            .POST = target,
            .PUT = target,
            .TRACE = target,
        },
    };
}

/// Match build helper for GET requests.
pub fn GET(comptime name: []const u8, comptime match: BuildFn) Match {
    return .{
        .name = name,
        .methods = .{
            .GET = buildTarget(match),
        },
    };
}

/// Match build helper for POST requests.
pub fn POST(comptime name: []const u8, comptime match: BuildFn) Match {
    return .{
        .name = name,
        .methods = .{
            .POST = buildTarget(match),
        },
    };
}

/// Match build helper for DELETE requests.
pub fn DELETE(comptime name: []const u8, comptime match: BuildFn) Match {
    return .{
        .name = name,
        .methods = .{
            .DELETE = buildTarget(match),
        },
    };
}

/// Static file helper that will auto route to the provided directory.
/// Verse normally expects to sit behind an rproxy, that can route requests for
/// static resources without calling Verse. But Verse does have some support for
/// returning simple static resources.
pub fn STATIC(comptime name: []const u8) Match {
    return .{
        .name = name,
        .methods = .{
            .GET = buildTarget(StaticFile.fileOnDisk),
        },
    };
}

/// Convenience build function that will return a default page, normally during
/// an error.
pub fn defaultResponse(comptime code: std.http.Status) BuildFn {
    return switch (code) {
        .not_found => notFound,
        .internal_server_error => internalServerError,
        else => default,
    };
}

fn notFound(vrs: *Verse) Error!void {
    vrs.status = .not_found;
    const E404 = @embedFile("fallback_html/404.html");
    try vrs.quickStart();
    return vrs.sendRawSlice(E404);
}

fn internalServerError(vrs: *Verse) Error!void {
    vrs.status = .internal_server_error;
    const E500 = @embedFile("fallback_html/500.html");
    try vrs.quickStart();
    return vrs.sendRawSlice(E500);
}

fn methodNotAllowed(vrs: *Verse) Error!void {
    vrs.status = .method_not_allowed;
    const E405 = @embedFile("fallback_html/405.html");
    try vrs.quickStart();
    return vrs.sendRawSlice(E405);
}

fn default(vrs: *Verse) Error!void {
    const index = @embedFile("fallback_html/index.html");
    try vrs.quickStart();
    return vrs.sendRawSlice(index);
}

pub const RoutingError = error{
    Unrouteable,
    MethodNotAllowed,
    NotFound,
};

/// Default routing function. This is likely the routing function you want to
/// provide to verse with the Match array for your site. It can also be used
/// internally within custom routing functions, that provide additional page,
/// data or routing support/validation, before continuing to build the route.
pub fn router(vrs: *Verse, comptime routes: []const Match) RoutingError!BuildFn {
    const search = vrs.uri.peek() orelse {
        if (routes.len > 0 and routes[0].name.len == 0) {
            switch (vrs.request.method) {
                inline else => |m| if (routes[0].target(m)) |t| return switch (t) {
                    .build => |b| return b,
                    .route, .simple => return error.Unrouteable,
                },
            }
        }

        log.warn("No endpoint found: URI is empty.", .{});
        return error.Unrouteable;
    };
    inline for (routes) |ep| {
        if (eql(u8, search, ep.name)) {
            switch (vrs.request.method) {
                inline else => |m| {
                    if (comptime ep.target(m)) |target| {
                        switch (target) {
                            .build => |call| {
                                return call;
                            },
                            .route => |route| {
                                return route(vrs) catch |err| switch (err) {
                                    error.Unrouteable => return notFound,
                                    else => unreachable,
                                };
                            },
                            inline .simple => |simple| {
                                _ = vrs.uri.next();
                                return router(vrs, simple);
                            },
                        }
                    } else return error.MethodNotAllowed;
                },
            }
        }
    }
    return error.Unrouteable;
}

/// The Verse Server is unlikely to be able to handle the various error states
/// an endpoint might generate. Pages are permitted to return an error, and the
/// page builder is required to handle all errors, and make a final decision.
/// Ideally it should also be able to return a response to the user, but that
/// implementation detail is left to the caller. This default builder is
/// provided and handles an abbreviated set of errors.
pub fn defaultBuilder(vrs: *Verse, build: BuildFn) void {
    build(vrs) catch |err| {
        switch (err) {
            error.NoSpaceLeft,
            error.OutOfMemory,
            => @panic("OOM"),
            error.BrokenPipe => log.warn("client disconnect", .{}),
            error.Unrouteable => {
                // Reaching an Unrouteable error here should be impossible as
                // the router has decided the target endpoint is correct.
                // However it's a vaild error in somecases. A non-default buildfn
                // could provide a replacement default. But this does not.
                log.err("Unrouteable", .{});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
                @panic("Unroutable");
            },
            error.NotImplemented,
            error.Unknown,
            => unreachable,
            // This is an implementation error by the page. So we crash. If
            // you've reached this, something is wrong with your site.
            error.InvalidURI,
            => log.err("Unexpected error '{}'\n", .{err}),
            error.Abusive,
            error.Unauthenticated,
            error.BadData,
            error.DataMissing,
            => {
                // BadData and DataMissing aren't likely to be abusive, but
                // dumping the information is likely to help with debugging the
                // error.
                log.err("Abusive {} because {}\n", .{ vrs.request, err });
                var itr = vrs.request.raw.http.iterateHeaders();
                while (itr.next()) |vars| {
                    log.err("Abusive var '{s}' => '''{s}'''\n", .{ vars.name, vars.value });
                }
            },
        }
    };
}

const root = [_]Match{
    ROUTE("", default),
};

fn defaultRouter(vrs: *Verse, routefn: RouteFn) BuildFn {
    return routefn(vrs) catch |err| switch (err) {
        error.MethodNotAllowed => methodNotAllowed,
        error.NotFound => notFound,
        error.Unrouteable => internalServerError,
    };
}

const root_with_static = root ++ [_]Match{
    ROUTE("static", StaticFile.file),
};

fn defaultRouterHtml(vrs: *Verse, routefn: RouteFn) Error!void {
    if (vrs.uri.peek()) |first| {
        if (first.len > 0)
            return routefn(vrs) catch router(vrs, &root_with_static) catch notFound;
    }
    return internalServerError;
}

pub fn testingRouter(v: *Verse) RoutingError!BuildFn {
    return router(v, &root);
}

const std = @import("std");
const log = std.log.scoped(.Verse);
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;

const Verse = @import("verse.zig");
const Request = @import("request.zig");
const StaticFile = @import("static-file.zig");
pub const Errors = @import("errors.zig");
pub const Error = Errors.ServerError || Errors.ClientError || Errors.NetworkError;
