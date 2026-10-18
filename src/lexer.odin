package glsr

import "core:unicode"
import "core:unicode/utf8"

input: string
input_length: int

lexer :: proc(inp: string) -> []Token {
	tokens := new([dynamic]Token)
	current_pos: int

	input = inp
	input_length = utf8.rune_count(input)

	for current_pos < input_length {
		token_start_pos := current_pos
		lookahead := rune_at(input, current_pos)

		if unicode.is_white_space(lookahead) {
			current_pos += 1
		} else if is_symbol(lookahead) {
			handle_symbols(&current_pos, tokens, token_start_pos, lookahead)
		} else if unicode.is_digit(lookahead) {
			handle_numbers(&current_pos, tokens, token_start_pos, lookahead)
		} else if is_letter(lookahead) {
			handle_words(&current_pos, tokens, token_start_pos, lookahead)
		} else {
			error(.LEXER, current_pos, "Unknown character '%v' (%U) at position %v", 
				lookahead, lookahead, current_pos)
		}
	}

	append(tokens, Token{.EOF, "<EOF>", current_pos})
	return tokens[:]
}

handle_symbols :: proc(current_pos: ^int, tokens: ^[dynamic]Token, token_start_pos: int, lookahead: rune) {
	runes := new([dynamic]rune)
	defer delete(runes^)

	type: Maybe(Token_Type)

	// These can be followed by other symbols but they should not be considered
	// part of a symbol array. E.g. (-4)*7
	switch lookahead {
	case '\'', '"': type = .QUOTE
	case '(': type = .PARENTHESIS_OPEN
	case ')': type = .PARENTHESIS_CLOSE
	case '[': type = .BRACKET_OPEN
	case ']': type = .BRACKET_CLOSE
	}

	if type != nil {
		append(tokens, Token{type.?, to_string(lookahead), token_start_pos})
		current_pos^ += 1
		return
	}

	// Proceed to symbol arrays (e.g. <-, >=, etc.)

	r := lookahead
	for current_pos^ < input_length && (is_symbol(r) && r != ' ') {
		append(runes, r)
		current_pos^ += 1
		r = rune_at(input, current_pos^)
	}

	symbol_array := utf8.runes_to_string(runes[:])

	switch symbol_array {
	case "+": type = .PLUS
	case "-": type = .MINUS
	case "*": type = .TIMES
	case "/": type = .FLOAT_DIV
	case "^": type = .POWER
	case "=": type = .EQUAL
	case "<>", "!=": type = .NOT_EQUAL
	case ">": type = .BIGGER
	case ">=": type = .BIGGER_EQUAL
	case "<": type = .SMALLER
	case "<=": type = .SMALLER_EQUAL
	case "<-": type = .ASSIGN
	case: error(.LEXER, current_pos^, "Unknown symbol array: %v", symbol_array)
	}

	append(tokens, Token{type.?, symbol_array, token_start_pos})
}

handle_numbers :: proc(current_pos: ^int, tokens: ^[dynamic]Token, token_start_pos: int, lookahead: rune) {
	has_dot_appeared: bool
	runes := new([dynamic]rune)
	defer delete(runes^)

	r := lookahead
	for current_pos^ < input_length && (unicode.is_digit(r) || r == '.') {
		if r == '.' {
			if !has_dot_appeared do has_dot_appeared = true; else do error(.LEXER, current_pos^, "Multiple dots!")
		}
		append(runes, r)

		current_pos^ += 1
		r = rune_at(input, current_pos^)
	}

	num_string := utf8.runes_to_string(runes[:])
	if runes[len(runes) - 1] == '.' do error(.LEXER, current_pos^, "Number ending with dot: %s", num_string)
	
	type := Token_Type.INT_LITERAL if !has_dot_appeared else Token_Type.FLOAT_LITERAL
	append(tokens, Token{type, num_string, token_start_pos})
}

handle_words :: proc(current_pos: ^int, tokens: ^[dynamic]Token, token_start_pos: int, lookahead: rune) {
	runes := new([dynamic]rune)
	defer delete(runes^)

	r := lookahead
	for current_pos^ < input_length && (unicode.is_digit(r) || is_letter(r) || r == '_') {
		append(runes, r)
		current_pos^ += 1
		r = rune_at(input, current_pos^)
	}

	word := utf8.runes_to_string(runes[:])
	type: Token_Type

	switch word {
	case "DIV": type = .DIV
	case "MOD": type = .MOD
	case "AND", "ΚΑΙ": type = .AND
	case "OR", "Η": type = .OR
	case "NOT", "ΟΧΙ": type = .NOT
	case "TRUE", "ΑΛΗΘΗΣ": type = .TRUE
	case "FALSE", "ΨΕΥΔΗΣ": type = .FALSE
	case: type = .IDENTIFIER
	}

	append(tokens, Token{type, word, token_start_pos})
}

to_number :: proc(char: rune) -> u8 {
	switch char {
	case '0': return 0
	case '1': return 1
	case '2': return 2
	case '3': return 3
	case '4': return 4
	case '5': return 5
	case '6': return 6
	case '7': return 7
	case '8': return 8
	case '9': return 9
	case: return 0
	}
}

to_string :: proc(char: rune) -> string {
	return utf8.runes_to_string([]rune{char})
}

rune_at :: proc(s: string, i: int) -> rune {
	return utf8.rune_at_pos(s, i)
}

is_letter :: proc(r: rune) -> bool {
	return ('\u0041' <= r && r <= '\u005A') || // Latin uppercase
           ('\u0061' <= r && r <= '\u007A') || // Latin lowercase
           ('\u0386' <= r && r <= '\u03CE' && r != '\u0387') // Greek
}

is_symbol :: proc(r: rune) -> bool {
	return ('\u0020' <= r && r <= '\u002F') ||
           ('\u003A' <= r && r <= '\u0040') ||
           ('\u005B' <= r && r <= '\u0060') ||
           ('\u007B' <= r && r <= '\u007E')
}

Token :: struct {
	type: Token_Type,
	value: string,
	start_pos: int,
}

Token_Type :: enum {
	// Literal
	INT_LITERAL,
	FLOAT_LITERAL,

	IDENTIFIER,

	// Logical
	AND,
	OR,
	NOT,

	TRUE,
	FALSE,

	// Arithmetic
	PLUS,
	MINUS,
	TIMES,
	FLOAT_DIV,
	DIV,
	MOD,
	POWER,

	// Comparative
	EQUAL,
	BIGGER,
	BIGGER_EQUAL,
	SMALLER,
	SMALLER_EQUAL,
	NOT_EQUAL,

	// Doubles
	QUOTE,
	PARENTHESIS_OPEN,
	PARENTHESIS_CLOSE,
	BRACKET_OPEN,
	BRACKET_CLOSE,

	ASSIGN,

	EOF,
}