package glsr

import "core:unicode"
import "core:fmt"

parse_expression :: proc(lexer: ^Lexer, min_bind_power: f64 = -1) -> Expression {
	// Fix to fit to the form <EOL> <reversed lexer>
	if lexer[0].type != .EOL {
		append(lexer, Token{.EOL, "<EOL>", 999})
		reverse(lexer)
	}
	
	left_hand_side: Expression
	{
		token := advance_lexer(lexer)
		#partial switch token.type {
		case .IDENTIFIER, .NUMBER_LITERAL, .BOOL_LITERAL, .STRING_LITERAL: left_hand_side = Atom(token.value)
		case .PARENTHESIS_OPEN:
			left_hand_side = parse_expression(lexer, 0)
			next := advance_lexer(lexer)
			if next.type != .PARENTHESIS_CLOSE do error("No closing parenthesis found!")
		case .NOT, .NUMERICAL_OPERATOR, .LOGICAL_OPERATOR, .COMPARATIVE_OPERATOR:
			if token.value != "ΟΧΙ" && token.value != "-" && token.value != "+" do error("Cannot perform unary operation with operator: '%s'", token.value)
			rhs := parse_expression(lexer, 100)	
            operation := new(Unary_Operation)
            operation^ = Unary_Operation{token.value, rhs}
            left_hand_side = operation
		case: error("Bad token! (lhs stage), got \"%v\"", token)
		}
	}

	loop: for true {
		operator: string
		{
			token := peek_lexer(lexer)
			#partial switch token.type {
			case .EOL, .PARENTHESIS_CLOSE: break loop
			case .NUMERICAL_OPERATOR, .LOGICAL_OPERATOR, .COMPARATIVE_OPERATOR, .ASSIGN: operator = token.value
			case: error("Bad token! (operator stage), got \"%v\"", token)
			}
		}

		left_bind_power, right_bind_power := binding_power(operator)
		if left_bind_power < min_bind_power do break loop

		advance_lexer(lexer)
	
		right_hand_side: Expression
		right_hand_side = parse_expression(lexer, right_bind_power)

		operation := new(Binary_Operation)
		operation^ = Binary_Operation{operator, left_hand_side, right_hand_side}
		left_hand_side = operation
	}
	
	return left_hand_side
}

@(private = "file")
append_line :: proc(lines: ^[dynamic]Lexer, current_line: ^Lexer) {
	if len(current_line) == 0 do return
	line_tokens := make([dynamic]Token)
    append(&line_tokens, ..current_line[:])
	append(lines, line_tokens)
}

parse_line :: proc(input_lexer: ^Lexer) -> Line {
	if len(input_lexer) == 0 do error("Nothing to parse!")
	
	lexer := make([dynamic]Token)
	defer delete(lexer)
	
	for token in input_lexer do append(&lexer, token)
	
	#partial switch lexer[0].type {
	case .PROGRAM:
		if len(lexer) == 1 do error("Missing program name!")
		if len(lexer) == 3 do error("Too many program names!")
		name := lexer[1].value
		if !is_valid_identifier_name(name) do error("Not a valid program name!")
		return Program_Statement{.DECLARATION, name}
	case .BEGIN_PROGRAM: return Program_Statement{.START, "START"}
	case .END_PROGRAM: return Program_Statement{.FINISH, "FINISH"}
	case .PRINT:
		if len(lexer) == 1 do error("Nothing to print!")

		result := make([dynamic]Expression)
		current_expr := make([dynamic]Token)
		
		for i := 1; i < len(lexer); i += 1 {
			token := lexer[i]
			if token.type != .COMMA { append(&current_expr, token); continue }
			
			expr := parse_expression(&current_expr)
			append(&result, expr)
			clear(&current_expr)
		}

		expr := parse_expression(&current_expr)
		append(&result, expr)
		delete(current_expr)

		return Print_Statement{ result[:] }
	case .READ:
		if len(lexer) == 1 do error("Nothing to read!")

		result := make([dynamic]string)
		reached_comma := true
		
		for i := 1; i < len(lexer); i += 1 {
			token := lexer[i]
			if token.type == .IDENTIFIER && reached_comma {
				if !reached_comma do error("Expected comma!")
				append(&result, token.value)
				reached_comma = false
				continue
			}
			
			if token.type == .COMMA { 
				reached_comma = true
				continue
			}

			error("Unable to read identifier: '%s'", token.value)
		}

		if reached_comma do error("Expected to read identifier!")

		return Read_Statement{ result[:] }
	case .VARIABLES: return Value_Type_Header{ .VARIABLE }
	case .CONSTANTS: return Value_Type_Header{ .CONSTANT }
	case .INTEGERS, .FLOATS, .STRINGS, .BOOLS:
		if lexer[1].type != .COLON do error("Expected colon!")
		
		if len(lexer) == 2 do error("No variables set!")

		result := make([dynamic]string)
		reached_comma := true
		
		for i := 2; i < len(lexer); i += 1 {
			token := lexer[i]
			if token.type == .IDENTIFIER && reached_comma {
				if !reached_comma do error("Expected comma!")
				append(&result, token.value)
				reached_comma = false
				continue
			}
			
			if token.type == .COMMA { 
				reached_comma = true
				continue
			}

			error("Unable to initialize variable: '%s'", token.value)
		}

		if reached_comma do error("Expected a variable name!")

		return Variable_Init_Statement{ lexer[0].type, result[:] }
	case .IF, .ELSE_IF:
		if lexer[len(lexer) - 1].type != .THEN do error("Expected 'THEN'!")
		token_slice := lexer[1 : len(lexer) - 1]
		if len(token_slice) == 0 do error("Found no logical expression!")

		tokens := make(Lexer)
		for token in token_slice do append(&tokens, token)

		return If_Statement{ .IF if lexer[0].type == .IF else .ELSE_IF, tokens }
	case .ELSE, .END_IF: return If_Statement{ .ELSE if lexer[0].type == .ELSE else .END_IF, nil }
	case .WHILE:
		if lexer[len(lexer) - 1].type != .REPEAT do error("Expected 'REPEAT'!")
		token_slice := lexer[1 : len(lexer) - 1]
		if len(token_slice) == 0 do error("Found no logical expression!")

		tokens := make(Lexer)
		for token in token_slice do append(&tokens, token)

		return While_Statement{ .START, tokens }
	case .END_REPEAT: return While_Statement{ .FINISH, nil }
	case .START_REPEAT: return Do_Until_Statement{ .START, nil }
	case .UNTIL:
		token_slice := lexer[1 : len(lexer)]
		if len(token_slice) == 0 do error("Found no logical expression!")

		tokens := make(Lexer)
		for token in token_slice do append(&tokens, token)

		return Do_Until_Statement{ .FINISH, tokens }
	}

	return parse_expression(input_lexer)
}

parse_program :: proc(lexer: Lexer) -> Program {
	result := make(Program)
	current_line := make(Lexer)
	lines := make([dynamic]Lexer)
	
	for token in lexer {
		if token.type != .NEW_LINE { append(&current_line, token); continue }
		if len(current_line) > 0 do append_line(&lines, &current_line)
		clear(&current_line)
	}

	if len(current_line) > 0 do append_line(&lines, &current_line)
		
	for &line, index in lines {
		if len(line) == 0 do continue
		append(&result, parse_line(&line))
		delete(line)
	}

	delete(current_line)
	delete(lines)

	return result
}

is_assignment_expr :: proc(expr: Expression, symbol_overload := "<-") -> Maybe( struct{str: string, exp: ^Expression} ) {
	switch v in expr {
	case Atom, ^Unary_Operation: return nil
	case ^Binary_Operation:
		if expr.(^Binary_Operation).operator == symbol_overload {
			name := cast(string)expr.(^Binary_Operation).left.(Atom)
			if !is_valid_identifier_name(name) do error("Invalid identifier name: %s", name)
			result: struct{str: string, exp: ^Expression} = { name, &expr.(^Binary_Operation).right }
			return result
		}
		return nil
	}
	unreachable()
}

is_valid_identifier_name :: proc(name: string) -> bool {
	if len(name) == 0 do return false
	for char, index in name {
		if is_letter(char) do continue
		if char == '_' && index > 0 do continue
		if unicode.is_digit(char) && index > 0 do continue
		return false
	}
	return true
} 

binding_power :: proc(operator: string) -> (f64, f64) {
	switch operator {
	case "<-": return 0.2, 0.1
		
	case "Η": return 10, 10.1
	case "ΚΑΙ": return 11, 11.1

	case "<", "<=", ">", ">=", "=", "<>": return 20, 20.1
		
	case "+", "-": return 30, 30.1
	case "*", "/", "DIV", "MOD": return 31, 31.1
	case "^": return 32.1, 32
	}

	error("Expected operand!")
}

Atom :: distinct string

Binary_Operation :: struct {
	operator: string,
	left: Expression,
	right: Expression,
}

Unary_Operation :: struct {
	operator: string,
	value: Expression,
}

Expression :: union {
	Atom,
	^Unary_Operation,
	^Binary_Operation,
}

Program_Statement :: struct { type: enum { DECLARATION, START, FINISH }, value: string }
Print_Statement :: struct { expr: []Expression }
Read_Statement :: struct { identifiers: []string }
Value_Type_Header :: struct { type: enum{ VARIABLE, CONSTANT } }
Variable_Init_Statement :: struct { type: Token_Type, variables: []string }
If_Statement :: struct { type: enum { IF, ELSE_IF, ELSE, END_IF }, condition_tokens: Lexer }
While_Statement :: struct { type: enum { START, FINISH }, condition_tokens: Lexer }
Do_Until_Statement :: struct { type: enum { START, FINISH }, condition_tokens: Lexer }

Line :: union {
	Expression,
	Program_Statement,
	Print_Statement,
	Read_Statement,
	Value_Type_Header,
	Variable_Init_Statement,
	If_Statement,
	While_Statement,
	Do_Until_Statement,
}

Program :: [dynamic]Line

@(private = "file")
error :: proc(message: string, args: ..any) -> ! {
	fmt.printf("[PARSER] %s\n", fmt.ctprintf(message, ..args) )
	panic("Interpreter encountered an error!")
}