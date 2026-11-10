#+private file

package glsr

import "core:unicode"
import "core:unicode/utf8"
import "core:strings"
import "core:fmt"

@(private) Lexer :: [dynamic]Token

dynamic_start_pos: struct{ line: int, pos: int } = {1, 0}
input: string
input_length: int
current_pos: int
token_start_pos: int
lookahead: rune

@(private)
peek_lexer :: proc(lexer: ^Lexer) -> Token {
	token := lexer[len(lexer) - 1] 
	return token
}

@(private)
advance_lexer :: proc(lexer: ^Lexer) -> Token {
	token := peek_lexer(lexer)
	pop(lexer)
	return token
}

@(private)
new_lexer :: proc(inp: string) -> Lexer {
	input = inp
	input_length = utf8.rune_count(input)

	lexer := new([dynamic]Token)
	current_pos = 0
	dynamic_start_pos = {1, 0}

	for current_pos < input_length {
		token_start_pos = current_pos
		lookahead = rune_at(current_pos)

		if is_ignorable(lookahead) {
			advance_tokenization()
		} else if is_symbol(lookahead) {
			handle_symbols(lexer)
		} else if unicode.is_digit(lookahead) {
			handle_numbers(lexer)
		} else if is_letter(lookahead) {
			handle_words(lexer)
		} else {
			error("Unknown character '%v' (%U)", 
				lookahead, lookahead)
		}
	}

	append(lexer, EOL_Token)

	reverse(lexer)

	return lexer^
}

@(private)
print_lexer :: proc(lexer: Lexer) {
	for token in lexer {
		fmt.printf("[%v, %s, %d]\n", token.type, token.value, token.start_pos)
	}
}

advance_tokenization :: proc(times := 1) {
	if times < 1 do return
	for i in 1..=times {
		current_pos += 1
		if lookahead == '\n' {
			dynamic_start_pos.line += 1
			dynamic_start_pos.pos = 0
		} else {
			dynamic_start_pos.pos += 1
		}
	}
}

handle_symbols :: proc(tokens: ^[dynamic]Token) {
	type: Token_Type
	next: Maybe(rune)
	str: string
	
	switch lookahead {
	case '\n': type = .NEW_LINE
	case '(': type = .PARENTHESIS_OPEN
	case ')': type = .PARENTHESIS_CLOSE
	case '[': type = .BRACKET_OPEN
	case ']': type = .BRACKET_CLOSE
	case ':': type = .COLON
	case ',': type = .COMMA
	case '+', '-', '*', '/', '^': type = .NUMERICAL_OPERATOR
	case '=': type = .COMPARATIVE_OPERATOR
	case '!': 
		str = recurse(proc(r: rune) -> bool { return r != '\n' }, true)
		type = .COMMENT
	case '\'', '"', 'ʽ', 'ʼ':
		str = recurse(proc(r: rune) -> bool { return r != '\'' && r != '"' && r != 'ʽ' && r != 'ʼ' }, true)

		r := rune_at(current_pos)
		matching_end_quote := (lookahead == '\'' && r == '\'') || (lookahead == '"' && r == '"') || 
			(lookahead == 'ʽ' && (r == 'ʽ' || r == 'ʼ'))
		if !matching_end_quote do error("No matching quote for '%v'!", lookahead)
		
		str = strings.concatenate({"\"", str}) // We do this to differentiate strings from variables when interpreting.
		type = .STRING_LITERAL
	case '<':
		next = rune_at(current_pos + 1)
		if next == '-' do type = .ASSIGN; else {
			type = .COMPARATIVE_OPERATOR
			if next != '>' && next != '=' do next = nil
		}
	case '>':
		next = rune_at(current_pos + 1)
		type = .COMPARATIVE_OPERATOR
		if next != '=' do next = nil
	case: error("Unknown symbol: %v", lookahead)
	}

	if str == "" do str = utf8.runes_to_string({lookahead, next.?} if next != nil else {lookahead})
	if type != .COMMENT do append(tokens, Token{type, str, token_start_pos}); else do append(tokens, Token{.NEW_LINE, "\n", token_start_pos})
	advance_tokenization(2 if next != nil else 1)
}

handle_numbers :: proc(tokens: ^[dynamic]Token) {
	is_float: bool
	r := lookahead
	
	for current_pos < input_length && unicode.is_digit(r) || r == '.' {
		advance_tokenization()
		r = rune_at(current_pos)

		if r == '.' {
			is_float = !is_float
			if !is_float do error("Multiple dots!")
		}
	}
	
	str := input[rune_pos(token_start_pos) : rune_pos(current_pos)]
	append(tokens, Token{.NUMBER_LITERAL, str, token_start_pos})
}

handle_words :: proc(tokens: ^[dynamic]Token) {	
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
	case "ΤΟΤΕ": type = .THEN

	case "ΟΣΟ": type = .WHILE
	case "ΕΠΑΝΑΛΑΒΕ": type = .REPEAT
	case "ΤΕΛΟΣ_ΕΠΑΝΑΛΗΨΗΣ": type = .END_REPEAT
		
	case "DIV", "MOD": type = .NUMERICAL_OPERATOR
		
	case "ΚΑΙ", "Η": type = .LOGICAL_OPERATOR
	case "ΟΧΙ": type = .NOT
		
	case "ΑΛΗΘΗΣ", "ΨΕΥΔΗΣ": type = .BOOL_LITERAL
	case: type = .IDENTIFIER
	}

	append(tokens, Token{type, word, token_start_pos})
}

// Recursively iterates over a condition, based on the current rune. When the condition is false,
// the recursion stops and the total rune array is returned as a string.
recurse :: proc(condition: proc(r: rune) -> bool, skip_first_rune := false) -> string {
	if skip_first_rune do advance_tokenization()
	r := rune_at(current_pos) if skip_first_rune else lookahead
	
	for current_pos < input_length && condition(r) {
		advance_tokenization()
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

@(private)
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

@(private)
Token :: struct {
	type: Token_Type,
	value: string,
	start_pos: int,
}

@(private)
Token_Type :: enum {
	IDENTIFIER,
	
	NUMBER_LITERAL,
	STRING_LITERAL,
	BOOL_LITERAL,

	NUMERICAL_OPERATOR,
	LOGICAL_OPERATOR,
	COMPARATIVE_OPERATOR,
	NOT,

	ASSIGN,

	NEW_LINE,

	COMMENT,

	QUOTE,
	PARENTHESIS_OPEN,
	PARENTHESIS_CLOSE,

	EOL,

	// NOT DONE ZONE:

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
	THEN,
	
	WHILE,
	REPEAT,
	END_REPEAT,
	
	COLON,
	COMMA,
	
	BRACKET_OPEN,
	BRACKET_CLOSE,
}

error :: proc(message: string, args: ..any) -> ! {
	fmt.printf("[LEXER] %s [%v]\n", fmt.ctprintf(message, ..args), dynamic_start_pos )
	panic("Interpreter encountered an error!")
}