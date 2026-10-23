package glsr

import "core:unicode"
import "core:unicode/utf8"

input: string
input_length: int

tokens: ^[dynamic]Token
current_pos: int

token_start_pos: int
lookahead: rune

tokenize :: proc(inp: string) -> []Token {
	input = inp
	input_length = utf8.rune_count(input)

	tokens = new([dynamic]Token)
	current_pos = 0

	for current_pos < input_length {
		token_start_pos = current_pos
		lookahead = rune_at(current_pos)

		if unicode.is_white_space(lookahead) {
			current_pos += 1
		} else if is_symbol(lookahead) {
			handle_symbols()
		} else if unicode.is_digit(lookahead) {
			handle_numbers()
		} else if is_letter(lookahead) {
			handle_words()
		} else {
			error(.LEXER, current_pos, "Unknown character '%v' (%U) at position %v", 
				lookahead, lookahead, current_pos)
		}
	}

	append(tokens, Token{.EOF, "<EOF>", current_pos})
	return tokens[:]
}

handle_symbols :: proc() {
	type: Token_Type
	next: Maybe(rune)
	
	switch lookahead {
	case '\'', '"': type = .QUOTE
	case '(': type = .PARENTHESIS_OPEN
	case ')': type = .PARENTHESIS_CLOSE
	case '[': type = .BRACKET_OPEN
	case ']': type = .BRACKET_CLOSE
	case '.': type = .DOT
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
	case: error(.LEXER, current_pos, "Unknown symbol: %v", lookahead)
	}

	str := utf8.runes_to_string({lookahead, next.?} if next != nil else {lookahead})
	append(tokens, Token{type, str, token_start_pos})
	current_pos += 2 if next != nil else 1
}

handle_numbers :: proc() {
	r := lookahead
	for current_pos < input_length && unicode.is_digit(r) {
		current_pos += 1
		r = rune_at(current_pos)
	}

	append(tokens, Token{.NUMBER, input[token_start_pos:current_pos], token_start_pos})
}

handle_words :: proc() {	
	r := lookahead
	for current_pos < input_length && (unicode.is_digit(r) || is_letter(r) || r == '_') {
		current_pos += 1
		r = rune_at(current_pos)
	}

	word := input[token_start_pos:current_pos]
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
           ('\u007B' <= r && r <= '\u007E')
}

Token :: struct {
	type: Token_Type,
	value: string,
	start_pos: int,
}

Token_Type :: enum {
	NUMBER,
	DOT,

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

	EOF,
}