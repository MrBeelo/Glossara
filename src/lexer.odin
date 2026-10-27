#+private file

package glsr

import "core:unicode"
import "core:unicode/utf8"

input: string
input_length: int

tokens: ^[dynamic]Token
current_pos: int
@(private) char_pos: struct{ line: int, pos: int } = {1, 0}

token_start_pos: int
lookahead: rune

advance :: proc(times := 1) {
	if times < 1 do return
	for i in 1..=times {
		current_pos += 1
		if lookahead == '\n' {
			char_pos.line += 1
			char_pos.pos = 0
		} else {
			char_pos.pos += 1
		}
	}
}

@(private)
tokenize :: proc(inp: string) -> []Token {
	input = inp
	input_length = utf8.rune_count(input)

	tokens = new([dynamic]Token)
	current_pos = 0
	char_pos = {1, 0}

	for current_pos < input_length {
		token_start_pos = current_pos
		lookahead = rune_at(current_pos)

		if is_ignorable(lookahead) {
			advance()
		} else if is_symbol(lookahead) {
			handle_symbols()
		} else if unicode.is_digit(lookahead) {
			handle_numbers()
		} else if is_letter(lookahead) || lookahead == '_' {
			handle_words()
		} else {
			error(.LEXER, "Unknown character '%v' (%U)", 
				lookahead, lookahead)
		}
	}

	append(tokens, Token{.EOF, "<EOF>", current_pos})
	return tokens[:]
}

handle_symbols :: proc() {
	type: Token_Type
	next: Maybe(rune)
	str: string
	
	switch lookahead {
	case '\n': type = .NEW_LINE
	case '(': type = .PARENTHESIS_OPEN
	case ')': type = .PARENTHESIS_CLOSE
	case '[': type = .BRACKET_OPEN
	case ']': type = .BRACKET_CLOSE
	case '.': type = .DOT
	case ':': type = .COLON
	case ',': type = .COMMA
	case '+': type = .PLUS
	case '-': type = .MINUS
	case '*': type = .TIMES
	case '/': type = .FLOAT_DIV
	case '^': type = .POWER
	case '=': type = .EQUAL
	case '!': 
		str = recurse(proc(r: rune) -> bool { return r != '\n' }, true)
		type = .COMMENT
	case '\'', '"', 'ʽ', 'ʼ':
		str = recurse(proc(r: rune) -> bool { return r != '\'' && r != '"' && r != 'ʽ' && r != 'ʼ' }, true)
		type = .STRING_LITERAL
	case '<':
		next = rune_at(current_pos + 1)
		switch next {
		case '>': type = .NOT_EQUAL // <>
		case '=': type = .SMALLER_EQUAL // <=
		case '-': type = .ASSIGN // <-
		case: type = .SMALLER; next = nil
		}
	case '>':
		next = rune_at(current_pos + 1)
		switch next {
		case '=': type = .BIGGER_EQUAL // >=
		case: type = .BIGGER; next = nil
		}
	case: error(.LEXER, "Unknown symbol: %v", lookahead)
	}

	if str == "" do str = utf8.runes_to_string({lookahead, next.?} if next != nil else {lookahead})
	append(tokens, Token{type, str, token_start_pos})
	advance(2 if next != nil else 1)
}

handle_numbers :: proc() {
	str := recurse(unicode.is_digit)
	append(tokens, Token{.NUMBER_LITERAL, str, token_start_pos})
}

handle_words :: proc() {	
	word := recurse(proc(r: rune) -> bool { return unicode.is_digit(r) || is_letter(r) || r == '_' })
	type: Token_Type

	switch word {
	case "ΠΡΟΓΡΑΜΜΑ": type = .PROGRAM
	case "ΑΡΧΗ": type = .BEGIN_PROGRAM
	case "ΤΕΛΟΣ_ΠΡΟΓΡΑΜΜΑΤΟΣ": type = .END_PROGRAM

	case "ΜΕΤΑΒΛΗΤΕΣ": type = .VARIABLES
	case "ΣΤΑΘΕΡΕΣ": type = .CONSTANTS
	case "ΑΚΕΡΑΙΕΣ": type = .INTEGERS
	case "ΠΡΑΓΜΑΤΙΚΕΣ": type = .FLOATS
	case "ΧΑΡΑΚΤΗΡΕΣ": type = .STRINGS
	case "ΛΟΓΙΚΕΣ": type = .BOOLS

	case "ΓΡΑΨΕ": type = .PRINT
	case "ΔΙΑΒΑΣΕ": type = .READ

	case "ΑΝ": type = .IF
	case "ΑΛΛΙΩΣ_ΑΝ": type = .ELSE_IF
	case "ΑΛΛΙΩΣ": type = .ELSE
	case "ΤΕΛΟΣ_ΑΝ": type = .END_IF

	case "ΟΣΟ": type = .WHILE
	case "ΕΠΑΝΑΛΑΒΕ": type = .REPEAT
	case "ΤΕΛΟΣ_ΕΠΑΝΑΛΗΨΗΣ": type = .END_REPEAT
		
	case "DIV": type = .DIV
	case "MOD": type = .MOD
		
	case "ΚΑΙ": type = .AND
	case "Η": type = .OR
	case "ΟΧΙ": type = .NOT
		
	case "ΑΛΗΘΗΣ", "ΨΕΥΔΗΣ": type = .BOOL_LITERAL
	case: type = .IDENTIFIER
	}

	append(tokens, Token{type, word, token_start_pos})
}

// Recursively iterates over a condition, based on the current rune. When the condition is false,
// the recursion stops and the total rune array is returned as a string.
recurse :: proc(condition: proc(r: rune) -> bool, skip_first_rune := false) -> string {
	if skip_first_rune do advance()
	r := rune_at(current_pos) if skip_first_rune else lookahead
	
	for current_pos < input_length && condition(r) {
		advance()
		r = rune_at(current_pos)
	}
	
	str := input[rune_pos(token_start_pos + (1 if skip_first_rune else 0)) : rune_pos(current_pos)]
	return str
}

rune_at :: proc(i: int) -> rune {
	return utf8.rune_at_pos(input, i)
}

rune_pos :: proc(p: int) -> int {
	result := utf8.rune_offset(input, p)
	if result == -1 do result = len(input)
	return result
}

is_letter :: proc(r: rune) -> bool {
	return ('\u0041' <= r && r <= '\u005A') || // Latin uppercase
           ('\u0061' <= r && r <= '\u007A') || // Latin lowercase
           ('\u0386' <= r && r <= '\u03CE' && r != '\u0387') // Greek
}

is_symbol :: proc(r: rune) -> bool {
	if r == '_' do return false // Should prob be treated as an identifier
	return ('\u0020' <= r && r <= '\u002F') ||
           ('\u003A' <= r && r <= '\u0040') ||
           ('\u005B' <= r && r <= '\u0060') ||
           ('\u007B' <= r && r <= '\u007E') ||
           ('\u02B0' <= r && r <= '\u02EE') ||
           r == '\n'
}

is_ignorable :: proc(r: rune) -> bool {
	return unicode.is_white_space(r) && r != '\n'
}

Token :: struct {
	type: Token_Type,
	value: string,
	start_pos: int,
}

Token_Type :: enum {
	IDENTIFIER,

	PROGRAM,
	BEGIN_PROGRAM,
	END_PROGRAM,
	
	VARIABLES,
	CONSTANTS,
	INTEGERS,
	FLOATS,
	STRINGS,
	BOOLS,

	PRINT,
	READ,
	
	IF,
	ELSE_IF,
	ELSE,
	END_IF,
	
	WHILE,
	REPEAT,
	END_REPEAT,

	DIV,
	MOD,

	AND,
	OR,
	NOT,
	
	NUMBER_LITERAL,
	STRING_LITERAL,
	BOOL_LITERAL,
	
	DOT,
	COLON,
	COMMA,

	PLUS,
	MINUS,
	TIMES,
	FLOAT_DIV,
	POWER,

	EQUAL,
	BIGGER,
	BIGGER_EQUAL,
	SMALLER,
	SMALLER_EQUAL,
	NOT_EQUAL,

	COMMENT,

	QUOTE,
	PARENTHESIS_OPEN,
	PARENTHESIS_CLOSE,
	BRACKET_OPEN,
	BRACKET_CLOSE,

	ASSIGN,

	NEW_LINE,

	EOF,
}