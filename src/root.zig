pub const fs = @import("file_system.zig");

// Current hack to run all tests on all imports
test {
    @import("std").testing.refAllDecls(@This());
}
