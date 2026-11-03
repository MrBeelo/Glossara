package glsr

import "core:unicode"
import "core:fmt"

parse_expression :: proc(lexer: Lexer, min_bind_power: f32 = -1) -> Expression {
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
			case .EOF, .PARENTHESIS_CLOSE: break loop
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

is_assignment_expr :: proc(expr: Expression) -> Maybe( struct{str: string, exp: ^Expression} ) {
	switch v in expr {
	case Atom, ^Unary_Operation: return nil
	case ^Binary_Operation:
		if expr.(^Binary_Operation).operator == "<-" {
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
		if char == '_' do continue
		if unicode.is_digit(char) && index > 0 do continue
		return false
	}
	return true
} 

binding_power :: proc(operator: string) -> (f32, f32) {
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

@(private = "file")
error :: proc(message: string, args: ..any) -> ! {
	fmt.printf("[PARSER] %s\n", fmt.ctprintf(message, ..args) )
	panic("Interpreter encountered an error!")
}