package glsr

import "core:unicode"
import "core:unicode/utf8"
import "core:fmt"

input: string
input_length: int

tokens: ^[dynamic]Token
current_pos: int
char_pos: struct{ line: int, pos: int } = {1, 0}

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

tokenize :: proc(inp: string) -> []Token {
	input = inp
	input_length = utf8.rune_count(input)

	tokens = new([dynamic]Token)
	current_pos = 0
	char_pos = {1, 0}

	for current_pos < input_length {
		token_start_pos = current_pos
		lookahead = rune_at(current_pos)

		if unicode.is_white_space(lookahead) {
			advance()
		} else if is_symbol(lookahead) {
			handle_symbols()
		} else if unicode.is_digit(lookahead) {
			handle_numbers()
		} else if is_letter(lookahead) {
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
	
	switch lookahead {
	case '\n': type = .NEW_LINE
	case '\'', '"', '`', 'ʽ', 'ʼ': type = .QUOTE
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

	str := utf8.runes_to_string({lookahead, next.?} if next != nil else {lookahead})
	append(tokens, Token{type, str, token_start_pos})
	advance(2 if next != nil else 1)
}

handle_numbers :: proc() {
	r := lookahead
	for current_pos < input_length && unicode.is_digit(r) {
		advance()
		r = rune_at(current_pos)
	}

	str := input[utf8.rune_offset(input, token_start_pos) : utf8.rune_offset(input, current_pos)]
	append(tokens, Token{.NUMBER, str, token_start_pos})
}

handle_words :: proc() {	
	r := lookahead
	for current_pos < input_length && (unicode.is_digit(r) || is_letter(r) || r == '_') {
		advance()
		r = rune_at(current_pos)
	}

	end_index := utf8.rune_offset(input, current_pos)
	if end_index == -1 do end_index = len(input)
	
	word := input[utf8.rune_offset(input, token_start_pos):end_index]
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

rune_at :: proc(i: int) -> rune {
	return utf8.rune_at_pos(input, i)
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
           ('\u007B' <= r && r <= '\u007E') ||
           ('\u02B0' <= r && r <= '\u02EE')
}

Token :: struct {
	type: Token_Type,
	value: string,
	start_pos: int,
}

Token_Type :: enum {
	NUMBER,
	DOT,
	COLON,
	COMMA,

	IDENTIFIER,

	AND,
	OR,
	NOT,

	TRUE,
	FALSE,

	PLUS,
	MINUS,
	TIMES,
	FLOAT_DIV,
	DIV,
	MOD,
	POWER,

	EQUAL,
	BIGGER,
	BIGGER_EQUAL,
	SMALLER,
	SMALLER_EQUAL,
	NOT_EQUAL,

	QUOTE,
	PARENTHESIS_OPEN,
	PARENTHESIS_CLOSE,
	BRACKET_OPEN,
	BRACKET_CLOSE,

	ASSIGN,

	NEW_LINE,

	EOF,
}