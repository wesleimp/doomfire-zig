const std = @import("std");
const Io = std.Io;
const Writer = std.Io.Writer;

// const fire = @import("fire");
// ESC[?1049h
const enter_altscreen = "\x1b[?1049h";
const clear_screen = "\x1b[2J";
const move_cursor_home = "\x1b[H";
const leave_alt_screen = "\x1b[?1049l";
const make_cursor_invisible = "\x1b[?25l";
const make_cursor_visible = "\x1b[?25h";

const palette = [37]u8{
    16, // #070707
    52, // #1f0707
    52, // #2f0f07
    52, // #470f07
    88, // #571707
    88, // #671f07
    88, // #771f07
    88, // #8f2707
    124, // #9f2f07
    124, // #af3f07
    130, // #bf4707
    130, // #c74707
    130, // #df4f07
    166, // #df5707
    166, // #df5707
    166, // #d75f07
    166, // #d75f07
    166, // #d7670f
    172, // #cf6f0f
    172, // #cf770f
    172, // #cf7f0f
    172, // #cf870f
    172, // #cf8717
    136, // #c78717
    136, // #c78f17
    136, // #c7971f
    136, // #bf9f1f
    136, // #bf9f1f
    142, // #bfa727
    142, // #bfa727
    142, // #bfaf2f
    142, // #b7af2f
    142, // #b7b72f
    142, // #b7b737
    186, // #cfcf6f
    187, // #dfdf9f
    230, // #efefc7
};

const FireState = struct {
    height: u16,
    width: u16,
    number_of_pixels: u16,
    fire_pixels: []u16,
    prng: std.Random.DefaultPrng,
    fire_intensity: f16,
    writer: *Writer,

    pub fn init(allocator: std.mem.Allocator, io: Io, writer: *Writer, height: u16, width: u16) !FireState {
        const num_of_pixels = width * height;
        const fire_pixels = try allocator.alloc(u16, num_of_pixels);
        @memset(fire_pixels, 0);

        var seed: u64 = undefined;
        io.random(std.mem.asBytes(&seed));

        return FireState{
            .height = height,
            .width = width,
            .fire_intensity = 0.3,
            .number_of_pixels = num_of_pixels,
            .fire_pixels = fire_pixels,
            .prng = std.Random.DefaultPrng.init(seed),
            .writer = writer,
        };
    }

    pub fn deinit(self: *FireState, allocator: std.mem.Allocator) void {
        allocator.free(self.fire_pixels);
    }

    pub fn create_fire_source(self: *FireState) void {
        for (0..self.width) |i| {
            const pixel = i + self.number_of_pixels - self.width;
            self.fire_pixels[pixel] = 36;
        }
    }

    pub fn render(self: FireState) !void {
        try self.writer.print("{s}", .{move_cursor_home});
        for (0..self.height) |row| {
            for (0..self.width) |column| {
                const pixel: u16 = @intCast(column + (self.width * row));
                const pixel_bottom: u16 = @intCast(column + (self.width * (row + 1)));

                const pixel_intensity = self.fire_pixels[pixel];
                const pixel_bottom_intensity = if (pixel_bottom < self.number_of_pixels) self.fire_pixels[pixel_bottom] else 0;

                try self.writer.print("\x1b[38;5;{d}m\x1b[48;5;{d}m▄\x1b[0m", .{ palette[pixel_bottom_intensity], palette[pixel_intensity] });
            }
            try self.writer.print("\n", .{});
        }
        try self.writer.print("\n", .{});
    }

    pub fn calculate_fire_propagation(self: *FireState) void {
        for (0..self.width) |row| {
            for (0..self.height) |column| {
                const pixel: u16 = @intCast(row + (self.width * column));
                self.update_fire_intensity(pixel);
            }
        }
    }

    pub fn update_fire_intensity(self: *FireState, pixel: u16) void {
        const pixel_below = pixel + self.width;
        if (pixel_below >= self.number_of_pixels) {
            return;
        }

        const decay = self.gen_decay();
        const below_pixel_intensity = self.fire_pixels[pixel_below];

        const pixel_decay_index = safe_apply_decay(pixel, decay);
        self.fire_pixels[pixel_decay_index] = safe_apply_decay(below_pixel_intensity, decay);
    }

    fn gen_decay(self: *FireState) u16 {
        const rand = self.prng.random();
        const random: u8 = @intCast(rand.intRangeAtMost(u32, 0, 10));
        const decay: u16 = @intFromFloat(@round(random * self.fire_intensity));
        return decay;
    }
};

fn safe_apply_decay(value: u16, decay: u16) u16 {
    const v = @as(i32, value) - @as(i32, decay);
    if (v < 0) {
        return 0;
    }
    return @intCast(v);
}

pub fn main(init: std.process.Init) !void {
    // This is appropriate for anything that lives as long as the process.
    const alloc: std.mem.Allocator = init.gpa;
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var fire: FireState = try .init(alloc, io, stdout, 30, 70);
    defer fire.deinit(alloc);

    try stdout.print("{s}", .{enter_altscreen});
    try stdout.print("{s}", .{clear_screen});
    try stdout.print("{s}", .{make_cursor_invisible});
    try stdout.print("{s}", .{move_cursor_home});

    fire.create_fire_source();
    try fire.render();

    while (true) {
        try io.sleep(.fromMilliseconds(50), .real);
        fire.calculate_fire_propagation();
        try fire.render();
    }

    try stdout.print("{s}", .{leave_alt_screen});
    try stdout.print("{s}", .{make_cursor_visible});
}
