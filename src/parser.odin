package glsr

import "core:math"
import "core:unicode"
import "core:unicode/utf8"
import "core:strconv"

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
			case .OPERATOR, .ASSIGN: operator = token.value
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

is_assignment_expr :: proc(expr: Expression) -> Maybe( struct{str: string, exp: ^Expression} ) {
	switch v in expr {
	case Atom: return nil
	case ^Operation:
		if expr.(^Operation).operator == "<-" {
			name := cast(string)expr.(^Operation).left.(Atom)
			if !is_valid_identifier_name(name) do error(.PARSER, "Invalid identifier name: %s", name)
			result: struct{str: string, exp: ^Expression} = { name, &expr.(^Operation).right }
			return result
		}
		return nil
	}
	unreachable()
}

evaluate_expression :: proc(expr: Expression) -> f32 {
	switch v in expr {
	case Atom:
		str := string(v)
		if unicode.is_digit(utf8.rune_at_pos(str, 0)) { 
			result, ok := strconv.parse_f32(str)
			if ok do return result
			error(.PARSER, "Unexpected error while parsing number, got \"%s\"", str)
		} else {
			result, ok := vars[str]
			if !ok do error(.PARSER, "Variable \"%s\" was not declared!", str)
			return result
		}
	case ^Operation:
		left := evaluate_expression(v.left)
		right := evaluate_expression(v.right)
		switch v.operator {
		case "+": return left + right
		case "-": return left - right
		case "*": return left * right
		case "/": return left / right
		case "DIV": error(.PARSER, "DIV not added yet, we're only working with floats!")
		case "MOD": error(.PARSER, "MOD not added yet, we're only working with floats!")
		case "^": return math.pow(left, right)
		case: error(.PARSER, "Bad operator: %s", v.operator)
		}
	}
	unreachable()
}

Atom :: distinct string

Operation :: struct {
	operator: string,
	left: Expression,
	right: Expression,
}

Expression :: union {
	Atom,
	^Operation,
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
	case "+", "-": return 1, 1.1
	case "*", "/", "DIV", "MOD": return 2, 2.1
	case "^": return 3.1, 3
	}

	error(.PARSER, "Expected operand!")
}