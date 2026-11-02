package glsr

import "core:math"
import "core:unicode"
import "core:unicode/utf8"
import "core:strconv"
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
			case .NUMERICAL_OPERATOR, .LOGICAL_OPERATOR, .COMPARATIVE_OPERATOR, .ASSIGN: operator = token.value
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

evaluate_expression :: proc(expr: Expression) -> Data_Type {
	switch v in expr {
	case Atom:
		str := string(v)
		
		if unicode.is_digit(utf8.rune_at_pos(str, 0)) { 
			result_int, is_int := strconv.parse_int(str)
			if is_int do return result_int

			result_f32, is_float := strconv.parse_f32(str)
			if is_float do return result_f32
			
			error(.PARSER, "Unexpected error while parsing number, got \"%s\"", str)
		}

		if str == "ΑΛΗΘΗΣ" do return true
		if str == "ΨΕΥΔΗΣ" do return false

		result, ok := vars[str]
		if !ok do error(.PARSER, "Variable \"%s\" was not declared!", str)
		return result
	case ^Operation:
		lhs := evaluate_expression(v.left)
		rhs := evaluate_expression(v.right)
		switch v.operator {
		case "+", "-", "*", "/", "DIV", "MOD", "^": return numeric_operation(lhs, rhs, v.operator)
		case "ΚΑΙ", "Η": return logical_operation(lhs, rhs, v.operator)
		case "<", "<=", ">", ">=", "=", "<>": return comparative_operation(lhs, rhs, v.operator)
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

type_of_dt :: proc(dt: Data_Type) -> typeid {
	switch v in dt {
	case int: return int
	case f32: return f32
	case bool: return bool
	case string: return string 
	}
	return nil
}

numeric_operation :: proc(lhs, rhs: Data_Type, op: string) -> Data_Type {
	if type_of_dt(lhs) == bool || type_of_dt(rhs) == bool do error(.PARSER, "Cannot operate numerically on bools!")
	if type_of_dt(lhs) == string || type_of_dt(rhs) == string do error(.PARSER, "Cannot operate numerically on strings!")

	lhs_is_int, rhs_is_int := type_of_dt(lhs) == int, type_of_dt(rhs) == int
	
	if lhs_is_int && rhs_is_int do switch op {
	case "+": return lhs.(int) + rhs.(int)
	case "-": return lhs.(int) - rhs.(int)
	case "*": return lhs.(int) * rhs.(int)
	case "/": return f32(lhs.(int)) / f32(rhs.(int))
	case "DIV": return lhs.(int) %% rhs.(int)
	case "MOD": return lhs.(int) % rhs.(int)
	case "^":
		result := math.pow(f32(lhs.(int)), f32(rhs.(int)))
		if f32(int(result)) == result do return int(result)
		return result
	}

	lhs_float := f32(lhs.(int)) if lhs_is_int else lhs.(f32)
	rhs_float := f32(rhs.(int)) if rhs_is_int else rhs.(f32)

	switch op {
	case "+": return lhs_float + rhs_float
	case "-": return lhs_float - rhs_float
	case "*": return lhs_float * rhs_float
	case "/": return lhs_float / rhs_float
	case "DIV": error(.PARSER, "Cannot perform DIV on floats!")
	case "MOD": error(.PARSER, "Cannot perform MOD on floats!")
	case "^": return math.pow(lhs_float, rhs_float)
	}
	
	unreachable()
}

comparative_operation :: proc(lhs, rhs: Data_Type, op: string) -> Data_Type {
	if type_of_dt(lhs) == bool || type_of_dt(rhs) == bool do error(.PARSER, "Cannot operate comparatively on bools!")
	if type_of_dt(lhs) == string && type_of_dt(rhs) != string do error(.PARSER, "Cannot operate comparatively on different types!")
	if type_of_dt(lhs) != string && type_of_dt(rhs) == string do error(.PARSER, "Cannot operate comparatively on different types!")
	
	if type_of_dt(lhs) == string && type_of_dt(rhs) == string {
		// TODO: String comparison stuff goes here!
		return true
	}

	lhs_float := f32(lhs.(int)) if type_of_dt(lhs) == int else lhs.(f32)
	rhs_float := f32(rhs.(int)) if type_of_dt(rhs) == int else rhs.(f32)

	switch op {
	case "<": return lhs_float < rhs_float
	case "<=": return lhs_float <= rhs_float
	case ">": return lhs_float > rhs_float
	case ">=": return lhs_float >= rhs_float
	case "=": return lhs_float == rhs_float
	case "<>": return lhs_float != rhs_float
	}

	unreachable()
}

logical_operation :: proc(lhs, rhs: Data_Type, op: string) -> Data_Type {
	if type_of_dt(lhs) != bool || type_of_dt(rhs) != bool do error(.PARSER, "Cannot operate logically on non-bools!")

	switch op {
	case "ΚΑΙ": return lhs.(bool) && rhs.(bool)
	case "Η": return lhs.(bool) || rhs.(bool)
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

	error(.PARSER, "Expected operand!")
}