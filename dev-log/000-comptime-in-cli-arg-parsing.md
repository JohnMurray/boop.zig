# `comptime` in CLI Argument Parsing
## 2025-02-17

While building a simple CLI paser, my desire was to create a parser that was similar to the one used in Go,
where flag values are assigned into local variables.

```go
var (
	name string
	age int
)
func main() {
	flag.StringVar(&name, "name", "John", "Name of the person")
	flag.IntVar(&age, "age", 0, "Age of the person")
	flag.Parse()
}
```

My attempt at this in Zig starts first with a parser struct similar to how the `flag` package above is used.

```zig
struct {
    options: ArrayList(option),

    pub fn addFlag(self: *@This(), comptime T: type, short: []const u8, long: []const u8, desc: []const u8, dest: *T) !void;
}
```

Some zig-specific changes here over the Go version is the use of `comptime T: type` to indicate the type
we're parsing and storing versus specific function names (`StringVar`, `IntVar`, etc). The effect of this
method is to create a new `option` in our list. We can then reference this later when parsing the input
args.

I could use the `option` struct just to store the flag state, but I'd also like to use it to handle all the
logic specific to an individual flag (matching flag values, parsing, displaying help text, etc). This feels
like a good separation of concerns. A top-level parser that orchestrates the broad actions, and individual
options that handle specific flag logic.

```zig
fn option(comptime T: type) type {
    return struct {
        receiver: *T = undefined,
        length: usize = 0,

        long_name: ?ArrayList(u8) = null,
        short_name: ?ArrayList(u8) = null,

        // pub fn parse...
    };
}
```

This worked, but left me with a couple of challenges that I had to work through:
  - How do I organize the type-specific parsing logic within the `option` struct?
  - Now that I've specialized a type, how do I store `option`s in the parser struct?

For the type-specific parsing logic, I first tried (and failed) to do something like:

```zig
var res: T = undefined;
comptime {
    if (@TypeOf(T) == i32) {
        res = parse_i32();
    } else {
        return error.InvalidType;
    }
}
return res;
```

This fails because I'm mixing runtime and compile-time logic. I'm also using `@TypeOf` incorrectly. After a lot
of trail and error, and re-typing my parse functions to have the same type signature, I landed at:

```zig
comptime var parse_fn: *const fn ([]const u8, *T) anyerror!void = undefined;
comptime {
    if (T == i32) {
        parse_fn = parse_i32;
    } else if (T == bool) {
        parse_fn = parse_bool;
    } else {
        @compileError("Unsupported option time: " ++ @typeName(T));
    }
}
try parse_fn(arg, self.receiver);
```

This now correctly separates compile-time and runtime logic. What was interesting to me was that I needed to use
`anyerror` to abstract over the potential union of error types that the parse functions could return. I believe
I could have created a new error union to use here, but that seemed verbose and I'm unsure of the benefits that
would give me. Maybe I'll revisit this later when I'm more familiar with Zig error handling.

The second challenge was storing the `option` structs in the parser. I wanted to store them in a list, but I
realized that what I'm doing here is trying to port my Java patterns into Zig and that I am effectively saying,
"I wish I could have a generic list and perform dynamic dispatch". However, when I step back and realize that
the number of types that I'll be supporting here is both small and fixed, I can just have a small amount of
duplication for the types I'm supporting.

```zig
struct {
    i32_options: ArrayList(option(i32)),
    bool_options: ArrayList(option(bool)),
    // ...
}
```

While `comptime` is proving to be a very useful and powerful feature, I think I need to stop and remind myself that
I shouldn't try to force it in all situations. Some repetition is fine and the code remains clear and easy to read.
It'll take more practice to understand when this feature should be used and when it should be avoided.
