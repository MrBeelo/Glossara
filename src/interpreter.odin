#+private file

package glsr

import "core:unicode"
import "core:unicode/utf8"
import "core:strconv"
import "core:math"
import "core:strings"
import "core:fmt"

@(private)
evaluate_expression :: proc(expr: Expression) -> Data_Type {
	switch v in expr {
	case Atom:
		str := string(v)
		
		if unicode.is_digit(utf8.rune_at_pos(str, 0)) { 
			result_int, is_int := strconv.parse_int(str)
			if is_int do return result_int

			result_f32, is_float := strconv.parse_f32(str)
			if is_float do return result_f32
			
			error("Unexpected error while parsing number, got \"%s\"", str)
		}

		if utf8.rune_at_pos(str, 0) == '"' do return strings.trim_prefix(str, "\"")

		if str == "ΑΛΗΘΗΣ" do return true
		if str == "ΨΕΥΔΗΣ" do return false

		result, ok := vars[str]
		if !ok do error("Variable \"%s\" was not declared!", str)
		return result
	case ^Unary_Operation:
		value := evaluate_expression(v.value)
		switch v.operator {
		case "ΟΧΙ":
			if type_of_dt(value) != bool do error("Cannot perform NOT on a non-boolean!")
			return !value.(bool)
		case "-":
			if type_of_dt(value) == int do return -value.(int)
			if type_of_dt(value) == f32 do return -value.(f32)
			error("Cannot negate a non-number!")
		case "+":
			if type_of_dt(value) == int || type_of_dt(value) == f32 do return value
			error("Defining a non-number as positive doesn't make sense!")
		}
	case ^Binary_Operation:
		lhs := evaluate_expression(v.left)
		rhs := evaluate_expression(v.right)
		switch v.operator {
		case "+", "-", "*", "/", "DIV", "MOD", "^": return numeric_operation(lhs, rhs, v.operator)
		case "ΚΑΙ", "Η": return logical_operation(lhs, rhs, v.operator)
		case "<", "<=", ">", ">=", "=", "<>": return comparative_operation(lhs, rhs, v.operator)
		case: error("Bad operator: %s", v.operator)
		}
	}
	unreachable()
}

numeric_operation :: proc(lhs, rhs: Data_Type, op: string) -> Data_Type {
	if type_of_dt(lhs) == bool || type_of_dt(rhs) == bool do error("Cannot operate numerically on bools!")
	if type_of_dt(lhs) == string || type_of_dt(rhs) == string do error("Cannot operate numerically on strings!")

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
	case "DIV": error("Cannot perform DIV on floats!")
	case "MOD": error("Cannot perform MOD on floats!")
	case "^": return math.pow(lhs_float, rhs_float)
	}
	
	unreachable()
}

xor :: proc(a, b: bool) -> bool { return (a && !b) || (b && !a) }

comparative_operation :: proc(lhs, rhs: Data_Type, op: string) -> Data_Type {	
	if type_of_dt(lhs) == bool || type_of_dt(rhs) == bool do error("Cannot operate comparatively on bools!")
	if xor(type_of_dt(lhs) == string, type_of_dt(rhs) == string) do error("Cannot operate comparatively on different types!")
	
	if type_of_dt(lhs) == string && type_of_dt(rhs) == string {
		llen, rlen := len(lhs.(string)), len(rhs.(string))
		size := min(llen, rlen)

		left_index, right_index: int

		loop: for i := 0; i < size; i += 1 {
			left_char, right_char := utf8.rune_at_pos(lhs.(string), i), utf8.rune_at_pos(rhs.(string), i)
			if int(left_char) != int(right_char) { 
				left_index, right_index = int(left_char), int(right_char)
				break loop 
			}
		}

		switch op {
		case "<": return left_index < right_index
		case "<=": return left_index <= right_index
		case ">": return left_index > right_index
		case ">=": return left_index >= right_index
		case "=": return left_index == right_index
		case "<>": return left_index != right_index
		}
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
	if type_of_dt(lhs) != bool || type_of_dt(rhs) != bool do error("Cannot operate logically on non-bools!")

	switch op {
	case "ΚΑΙ": return lhs.(bool) && rhs.(bool)
	case "Η": return lhs.(bool) || rhs.(bool)
	}

	unreachable()
}

error :: proc(message: string, args: ..any) -> ! {
	fmt.printf("[INTERPRETER] %s\n", fmt.ctprintf(message, ..args) )
	panic("Interpreter encountered an error!")
}