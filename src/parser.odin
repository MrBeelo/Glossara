package glsr

parse_expression :: proc(lexer: Lexer) -> Expression {
	left_hand_side := new(Expression)
	{
		token := advance_lexer(lexer)
		#partial switch token.type {
		case .NUMBER_LITERAL, .IDENTIFIER: left_hand_side^ = Atom(token.value)
		case: error(.PARSER, "Bad token! (lhs stage)")
		}
	}
	
	operator: string
	{
		token := peek_lexer(lexer)
		#partial switch token.type {
		case .EOF: return left_hand_side^
		case .OPERATOR: operator = token.value
		case: error(.PARSER, "Bad token! (operator stage)")
		}
	}

	advance_lexer(lexer)

	right_hand_side := new(Expression)
	{
		token := advance_lexer(lexer)
		#partial switch token.type {
		case .NUMBER_LITERAL, .IDENTIFIER: right_hand_side^ = Atom(token.value)
		case: error(.PARSER, "Bad token! (rhs stage)")
		}
	}

	
	return Operation{operator, left_hand_side, right_hand_side}
}

Atom :: distinct string

Operation :: struct {
	op: string,
	left: ^Expression,
	right: ^Expression,
}

Expression :: union {
	Atom,
	Operation,
}

binding_power :: proc(operator: string) -> [2]f32 {
	switch operator {
	case "+", "-": return {1, 1.1}
	case "*", "/", "DIV", "MOD": return {2, 2.1}
	case "^": return {3, 3.1}
	}

	error(.PARSER, "Expected operand!")
}