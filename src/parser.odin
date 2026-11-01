package glsr

import "core:fmt"

parse_expression :: proc(lexer: Lexer, min_bind_power: f32 = -1) -> Expression {
	left_hand_side: Expression
	{
		token := advance_lexer(lexer)
		#partial switch token.type {
		case .NUMBER_LITERAL, .IDENTIFIER: left_hand_side = Atom(token.value)
		case .PARENTHESIS_OPEN:
			left_hand_side = parse_expression(lexer, 0)
			next := advance_lexer(lexer)
			if next.type != .PARENTHESIS_CLOSE do error(.PARSER, "No closing parenthesis found!")
		case: error(.PARSER, "Bad token! (lhs stage), got \"%v\"", token)
		}
	}

	loop: for true {
		operator: string
		{
			token := peek_lexer(lexer)
			#partial switch token.type {
			case .EOF, .PARENTHESIS_CLOSE: break loop
			case .OPERATOR: operator = token.value
			case: error(.PARSER, "Bad token! (operator stage), got \"%v\"", token)
			}
		}

		left_bind_power, right_bind_power := binding_power(operator)
		if left_bind_power < min_bind_power do break loop

		advance_lexer(lexer)
	
		right_hand_side: Expression
		right_hand_side = parse_expression(lexer, right_bind_power)

		operation := new(Operation)
		operation^ = Operation{operator, left_hand_side, right_hand_side}
		left_hand_side = operation
	}
	
	return left_hand_side
}

Atom :: distinct string

Operation :: struct {
	op: string,
	left: Expression,
	right: Expression,
}

Expression :: union {
	Atom,
	^Operation,
}

binding_power :: proc(operator: string) -> (f32, f32) {
	switch operator {
	case "+", "-": return 1, 1.1
	case "*", "/", "DIV", "MOD": return 2, 2.1
	case "^": return 3.1, 3
	}

	error(.PARSER, "Expected operand!")
}