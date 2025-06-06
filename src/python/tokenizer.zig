const std = @import("std");

pub const TokenType = enum {
    indent,
    dedent,
    newline,
    identifier,
    keyword,
    integer,
    string,
    lparen,
    rparen,
    colon,
    comma,
    plus,
    minus,
    star,
    slash,
    eq,
    eqeq,
    eof,
};

pub const Token = struct {
    typ: TokenType,
    lexeme: []const u8,
    line: usize,
    column: usize,
};

pub const Tokenizer = struct {
    source: []const u8,
    pos: usize,
    at_line_start: bool,
    indent_stack: std.ArrayList(usize),
    pending_dedents: usize,
    line: usize,
    column: usize,

    pub fn init(allocator: std.mem.Allocator, source: []const u8) Tokenizer {
        return .{
            .source = source,
            .pos = 0,
            .at_line_start = true,
            .indent_stack = std.ArrayList(usize).init(allocator),
            .pending_dedents = 0,
            .line = 1,
            .column = 1,
        };
    }

    pub fn deinit(self: *Tokenizer) void {
        self.indent_stack.deinit();
    }

    fn peek(self: *Tokenizer) ?u8 {
        if (self.pos < self.source.len) return self.source[self.pos];
        return null;
    }

    fn advance(self: *Tokenizer) ?u8 {
        if (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            self.pos += 1;
            if (ch == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            return ch;
        }
        return null;
    }

    pub fn next(self: *Tokenizer) Token {
        if (self.pending_dedents > 0) {
            self.pending_dedents -= 1;
            return Token{ .typ = .dedent, .lexeme = "", .line = self.line, .column = 1 };
        }

        while (true) {
            if (self.pos >= self.source.len) {
                if (self.indent_stack.items.len > 0) {
                    _ = self.indent_stack.pop();
                    return Token{ .typ = .dedent, .lexeme = "", .line = self.line, .column = 1 };
                }
                return Token{ .typ = .eof, .lexeme = "", .line = self.line, .column = self.column };
            }

            if (self.at_line_start) {
                var indent: usize = 0;
                while (self.peek()) |ch_space| {
                    if (ch_space == ' ') {
                        _ = self.advance();
                        indent += 1;
                    } else if (ch_space == '\t') {
                        _ = self.advance();
                        indent += 4;
                    } else {
                        break;
                    }
                }

                if (self.peek() == '#') {
                    while (self.peek()) |c| {
                        if (c == '\n') break;
                        _ = self.advance();
                    }
                }

                if (self.peek() == '\n') {
                    const start_line = self.line;
                    const start_column = self.column;
                    _ = self.advance();
                    self.at_line_start = true;
                    return Token{ .typ = .newline, .lexeme = "", .line = start_line, .column = start_column };
                }

                const current_indent = if (self.indent_stack.items.len == 0) 0 else self.indent_stack.items[self.indent_stack.items.len - 1];
                if (indent > current_indent) {
                    self.indent_stack.append(indent) catch unreachable;
                    self.at_line_start = false;
                    return Token{ .typ = .indent, .lexeme = "", .line = self.line, .column = 1 };
                } else if (indent < current_indent) {
                    while (self.indent_stack.items.len > 0 and self.indent_stack.items[self.indent_stack.items.len - 1] > indent) {
                        _ = self.indent_stack.pop();
                        self.pending_dedents += 1;
                    }
                    if (self.indent_stack.items.len == 0) {
                        if (indent != 0) return Token{ .typ = .eof, .lexeme = "", .line = self.line, .column = self.column };
                    } else {
                        if (indent != self.indent_stack.items[self.indent_stack.items.len - 1]) {
                            return Token{ .typ = .eof, .lexeme = "", .line = self.line, .column = self.column };
                        }
                    }
                    if (self.pending_dedents > 0) {
                        self.pending_dedents -= 1;
                        self.at_line_start = false;
                        return Token{ .typ = .dedent, .lexeme = "", .line = self.line, .column = 1 };
                    }
                }
                self.at_line_start = false;
            }

            const ch = self.peek().?;
            if (ch == ' ' or ch == '\t') {
                _ = self.advance();
                continue;
            }
            if (ch == '\n') {
                const start_line = self.line;
                const start_column = self.column;
                _ = self.advance();
                self.at_line_start = true;
                return Token{ .typ = .newline, .lexeme = "", .line = start_line, .column = start_column };
            }
            if (ch == '#') {
                const start_line = self.line;
                const start_column = self.column;
                while (self.peek()) |c2| {
                    _ = self.advance();
                    if (c2 == '\n') break;
                }
                self.at_line_start = true;
                return Token{ .typ = .newline, .lexeme = "", .line = start_line, .column = start_column };
            }
            if (std.ascii.isAlphabetic(ch) or ch == '_') {
                const start_line = self.line;
                const start_column = self.column;
                const start = self.pos;
                _ = self.advance();
                while (self.peek()) |c2| {
                    if (std.ascii.isAlphanumeric(c2) or c2 == '_') {
                        _ = self.advance();
                    } else break;
                }
                const slice = self.source[start..self.pos];
                if (isKeyword(slice)) {
                    return Token{ .typ = .keyword, .lexeme = slice, .line = start_line, .column = start_column };
                } else {
                    return Token{ .typ = .identifier, .lexeme = slice, .line = start_line, .column = start_column };
                }
            }
            if (std.ascii.isDigit(ch)) {
                const start_line = self.line;
                const start_column = self.column;
                const start = self.pos;
                _ = self.advance();
                while (self.peek()) |c2| {
                    if (std.ascii.isDigit(c2)) {
                        _ = self.advance();
                    } else break;
                }
                return Token{ .typ = .integer, .lexeme = self.source[start..self.pos], .line = start_line, .column = start_column };
            }
            if (ch == '\'' or ch == '"') {
                const start_line = self.line;
                const start_column = self.column;
                const quote = ch;
                _ = self.advance();
                const start = self.pos;
                while (self.peek()) |c2| {
                    _ = self.advance();
                    if (c2 == quote) break;
                }
                return Token{ .typ = .string, .lexeme = self.source[start .. self.pos - 1], .line = start_line, .column = start_column };
            }

            const start_line = self.line;
            const start_column = self.column;
            _ = self.advance();
            return switch (ch) {
                '(' => Token{ .typ = .lparen, .lexeme = "", .line = start_line, .column = start_column },
                ')' => Token{ .typ = .rparen, .lexeme = "", .line = start_line, .column = start_column },
                ':' => Token{ .typ = .colon, .lexeme = "", .line = start_line, .column = start_column },
                ',' => Token{ .typ = .comma, .lexeme = "", .line = start_line, .column = start_column },
                '+' => Token{ .typ = .plus, .lexeme = "", .line = start_line, .column = start_column },
                '-' => Token{ .typ = .minus, .lexeme = "", .line = start_line, .column = start_column },
                '*' => Token{ .typ = .star, .lexeme = "", .line = start_line, .column = start_column },
                '/' => Token{ .typ = .slash, .lexeme = "", .line = start_line, .column = start_column },
                '=' => blk: {
                    if (self.peek()) |peek_ch| {
                        if (peek_ch == '=') {
                            _ = self.advance();
                            break :blk Token{ .typ = .eqeq, .lexeme = "", .line = start_line, .column = start_column };
                        } else {
                            break :blk Token{ .typ = .eq, .lexeme = "", .line = start_line, .column = start_column };
                        }
                    } else {
                        break :blk Token{ .typ = .eq, .lexeme = "", .line = start_line, .column = start_column };
                    }
                },
                else => Token{ .typ = .eof, .lexeme = "", .line = self.line, .column = self.column },
            };
        }
    }

    fn isKeyword(bytes: []const u8) bool {
        const keywords = [_][]const u8{
            "def", "return", "if", "else", "while", "for", "in", "pass",
        };
        for (keywords) |kw| {
            if (std.mem.eql(u8, bytes, kw)) return true;
        }
        return false;
    }
};

fn expectToken(t: *Tokenizer, ty: TokenType, lex: []const u8, line: usize, column: usize) !void {
    const token = t.next();
    try std.testing.expectEqual(ty, token.typ);
    if (lex.len > 0) {
        try std.testing.expectEqualStrings(lex, token.lexeme);
    }
    try std.testing.expectEqual(line, token.line);
    try std.testing.expectEqual(column, token.column);
}

test "simple assignment" {
    var tokenizer = Tokenizer.init(std.testing.allocator, "x = 42\n");
    defer tokenizer.deinit();

    try expectToken(&tokenizer, .identifier, "x", 1, 1);
    try expectToken(&tokenizer, .eq, "", 1, 3);
    try expectToken(&tokenizer, .integer, "42", 1, 5);
    try expectToken(&tokenizer, .newline, "", 1, 7);
    try expectToken(&tokenizer, .eof, "", 2, 1);
}

test "def with indent" {
    const src = "def foo():\n    return 1\n";
    var tokenizer = Tokenizer.init(std.testing.allocator, src);
    defer tokenizer.deinit();

    try expectToken(&tokenizer, .keyword, "def", 1, 1);
    try expectToken(&tokenizer, .identifier, "foo", 1, 5);
    try expectToken(&tokenizer, .lparen, "", 1, 8);
    try expectToken(&tokenizer, .rparen, "", 1, 9);
    try expectToken(&tokenizer, .colon, "", 1, 10);
    try expectToken(&tokenizer, .newline, "", 1, 11);
    try expectToken(&tokenizer, .indent, "", 2, 1);
    try expectToken(&tokenizer, .keyword, "return", 2, 5);
    try expectToken(&tokenizer, .integer, "1", 2, 12);
    try expectToken(&tokenizer, .newline, "", 2, 13);
    try expectToken(&tokenizer, .dedent, "", 3, 1);
    try expectToken(&tokenizer, .eof, "", 3, 1);
}

test "string literal" {
    const src = "print(\"hi\")\n";
    var tokenizer = Tokenizer.init(std.testing.allocator, src);
    defer tokenizer.deinit();

    try expectToken(&tokenizer, .identifier, "print", 1, 1);
    try expectToken(&tokenizer, .lparen, "", 1, 6);
    try expectToken(&tokenizer, .string, "hi", 1, 7);
    try expectToken(&tokenizer, .rparen, "", 1, 11);
    try expectToken(&tokenizer, .newline, "", 1, 12);
    try expectToken(&tokenizer, .eof, "", 2, 1);
}
