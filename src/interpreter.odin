#+private file

package glsr

import "core:unicode"
import "core:unicode/utf8"
import "core:strconv"
import "core:math"
import "core:strings"
import "core:fmt"
import "core:os"

program_name: string
program_started, program_ended: bool
current_line: int

interpret_statement :: proc(line: Line, program: Program) {
	stmt := line.(Statement)
	switch x in stmt {
	case Program_Statement:
		switch x.type {
		case .DECLARATION: error("Double program name declaration!")
		case .START: 
			if program_started do error("Program has already started!")
			program_started = true
		case .FINISH:
			if !program_started do error("Program isn't running!")
			if program_ended do error("Program has already ended!")
			program_ended = true
		}
	case Print_Statement:
		if !program_started || program_ended do error("Cannot print anything while program isn't running!")
		#reverse for expr in x.expr do print_data_type(evaluate_expression(expr))
		fmt.printf("\n")
	case Read_Statement:
		if !program_started || program_ended do error("Cannot read anything while program isn't running!")
		#reverse for id in x.identifiers do read_data_type(id)
	case Value_Type_Header:
		header := stmt.(Value_Type_Header).type
		switch header {
		case .CONSTANT: interpret_constant_header(program)
		case .VARIABLE: interpret_variable_header(program)
		}
	case Variable_Init_Statement: error("Unexpected variable initialization statement!")
	}
}

interpret_constant_header :: proc(program: Program) {
	current_line += 1
	assignments := 0
	loop: for ; current_line < len(program); current_line += 1 {
		subline := program[current_line]
		switch v in subline {
		case Expression:
			if res := is_assignment_expr(v, "="); res != nil {
				assignments += 1
				values[res.?.str] = const_of(evaluate_expression(res.?.exp^))
			} else {
				error("Expected constant declaration!")
			}
		case Statement: switch w in v {
			case Print_Statement, Read_Statement: error("Expected some constant declaration, got %v!", w)
			case Program_Statement:
				if w.type != .START do error("Unexpected program statement!")
				if assignments == 0 do error("Got no constant assignments!")
				break loop
			case Value_Type_Header:
				if w.type == .CONSTANT do error("Duplicate constant header!")
				if assignments == 0 do error("Got no constant assignments!")
				break loop
			case Variable_Init_Statement: error("Expected constant declaraion, not variable!")
		}
			
		}
	}
	current_line -= 1
}

interpret_variable_header :: proc(program: Program) {
	current_line += 1
	reached_type: bool
	loop: for ; current_line < len(program); current_line += 1 {
		subline := program[current_line]
		switch v in subline {
		case Expression: error("Expected variable declaration, got expression!")
		case Statement: switch w in v {
			case Print_Statement, Read_Statement: error("Expected some constant declaration, got %v!", w)
			case Program_Statement:
				if w.type != .START do error("Unexpected program statement!")
				if reached_type == false do error("Got no variable declarations!")
				break loop
			case Value_Type_Header:
				if w.type == .VARIABLE do error("Duplicate variable header!")
				if reached_type == false do error("Got no variable declarations!")
				break loop
			case Variable_Init_Statement: 
				for var in w.variables {
					#partial switch w.type {
					case .INTEGERS: values[var] = var_of(int(0), false) 
					case .FLOATS: values[var] = var_of(f32(0), false)
					case .STRINGS: values[var] = var_of("", false)
					case .BOOLS: values[var] = var_of(false, false)
					}
				}
				reached_type = true
			}
		}
	}
	current_line -= 1
}

interpret_expression :: proc(line: Line) {
	if !program_started || program_ended do error("Cannot calculate expressions while program isn't running!")
	expr := line.(Expression)
	
	info := is_assignment_expr(expr)
	if info == nil do error("Unhandled expression!")
	
	_, ok := values[info.?.str]
	if !ok do error("Unknown value: '%s'!", info.?.str)

	value := evaluate_expression(info.?.exp^)
	if !values[info.?.str].variable do error("Cannot assign to a constant!")
	if type_of_dt(values[info.?.str].type) != type_of_dt(value) do error("Cannot assign value '%v' to variable '%s' of type '%v'!", value, info.?.str, type_of_dt(values[info.?.str].type))
	values[info.?.str] = var_of(value)
}

@(private)
run_program :: proc(program: Program) {
	current_line = 0
	for ; current_line < len(program); current_line += 1 {
		line := program[current_line]
		if current_line == 0 {
			stmt, stmt_ok := line.(Statement)
			if !stmt_ok do error("Expected program name declaration at the start!")
			pstmt, pstmt_ok := stmt.(Program_Statement)
			if !pstmt_ok do error("Expected program name declaration at the start!")
			program_name = pstmt.value
			continue
		}

		switch v in line {
		case Statement: interpret_statement(line, program)
		case Expression: interpret_expression(line)
		}
	}

	if !program_started do error("Nothing to do, program hasn't started!")
	if program_started && !program_ended do error("Program is unfinished!")
	fmt.printf("[Program %s finished succesfully.]\n", program_name)
}

print_data_type :: proc(dt: Data_Type) {
	switch v in dt {
	case int, f32, string: fmt.printf("%v", v)
	case bool: fmt.printf("ΑΛΗΘΗΣ" if v else "ΨΕΥΔΗΣ")
	}
}

read_data_type :: proc(id: string) {
	_, id_exists := values[id]
	if !id_exists do error("Can't read to unknown variable: %s!", id)

	if !values[id].variable do error("Cannot read to a constant!")

	if type_of_dt(values[id].type) == bool do error("Cannot read to bools!")
	
	buf: [256]u8
	out, err := os.read(os.stdin, buf[:])
	if err != nil do error("Error reading identifier: %v!", err)
	
	str := string(buf[:out-1])
	switch type_of_dt(values[id].type) {
	case int:
		result, ok := strconv.parse_int(str)
		if !ok do error("Error parsing integer: '%s'!", str)
		values[id] = var_of(result)
	case f32:
		result, ok := strconv.parse_f32(str)
		if !ok do error("Error parsing float!")
		values[id] = var_of(result)
	case bool:
		// Note: Bools cannot be read, but if they could, it would look like this:
		if str == "ΑΛΗΘΗΣ" do values[id] = var_of(true)
		if str == "ΨΕΥΔΗΣ" do values[id] = var_of(false)
		if str != "ΑΛΗΘΗΣ" && str != "ΨΕΥΔΗΣ" do error("Tried to read %s, which is not a bool!", str)
	case string: values[id] = var_of(str)
	}
}

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

		result, ok := get_value(str)
		if !ok do error("Value \"%s\" was not declared or is undefined!", str)
		return result.type
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

can_compare :: proc(left, right: Data_Type) -> bool {
	lt, rt := type_of_dt(left), type_of_dt(right)
	if lt == string && rt != string do return false
	if lt != string && rt == string do return false
	if lt == bool && rt != bool do return false
	if lt != bool && rt == bool do return false
	return true
}

comparative_operation :: proc(lhs, rhs: Data_Type, op: string) -> Data_Type {
	if !can_compare(lhs, rhs) do error("Cannot operate comparatively on different types!")

	if type_of_dt(lhs) == bool && type_of_dt(rhs) == bool {
		switch op {
		case "=": return lhs.(bool) == rhs.(bool)
		case "<>": return lhs.(bool) != rhs.(bool)
		case "<", "<=", ">", ">=": error("Cannot do comparison '%s' on bools!", op)
		}
	}
	
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
	state: string = ("INACTIVE" if !program_started else
		"ACTIVE" if program_started && !program_ended else "FINISHED")
	fmt.printf("[INTERPRETER] %s [current_line=%d, name=%s, state=%s]\n", fmt.ctprintf(message, ..args), 
		current_line + 1, program_name, state )
	panic("Interpreter encountered an error!")
}