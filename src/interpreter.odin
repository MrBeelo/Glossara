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

interpret_line :: proc(line: Line, program: Program) {
	switch x in line {
	case Expression: interpret_expression(line)
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
		for expr in x.expr do print_data_type(evaluate_expression(expr))
		fmt.printf("\n")
	case Read_Statement:
		if !program_started || program_ended do error("Cannot read anything while program isn't running!")
		for id in x.identifiers do read_data_type(id)
	case Value_Type_Header:
		header := line.(Value_Type_Header).type
		switch header {
		case .CONSTANT: interpret_constant_header(program)
		case .VARIABLE: interpret_variable_header(program)
		}
	case Variable_Init_Statement: error("Unexpected variable initialization statement!")
	case If_Statement: interpret_if_statement(x, program)
	case While_Statement: interpret_while_statement(x, program)
	case Do_Until_Statement: interpret_do_until_statement(x, program)
	case For_Statement: interpret_for_statement(x, program)
	case Loop_End_Statement: error("Unexpected loop finish statement!")
	case Switch_Statement: interpret_switch_statement(x, program)
	case Switch_Case_Statement: error("Unexpected switch case statement!")
	}
}

get_condition :: proc(lexer: Lexer) -> bool {
	lexer := lexer
	expr := parse_expression(&lexer)
	value := evaluate_expression(expr)
	
	if type_of_dt(value) != bool do error("Expected logical expression!")
	return value.(bool)
}

get_if_statement_condition :: proc(stmt: If_Statement) -> bool {
	if stmt.type == .ELSE || stmt.type == .END_IF do error("Cannot get condition of '%v' statement!", stmt.type)
	return get_condition(stmt.condition_tokens)
}

interpret_if_statement :: proc(stmt: If_Statement, program: Program) {
	if stmt.type != .IF do error("Unexpected if statement of type '%v'!", stmt.type)
	
	in_zone := get_if_statement_condition(stmt)
	have_entered_zone := in_zone

	current_line += 1
	scope_level: int
	
	for ; current_line < len(program); current_line += 1 {
		subline := program[current_line]
		
		#partial switch x in subline {
		case If_Statement:
			switch x.type {
			case .IF:
				if in_zone do interpret_if_statement(x, program); else do scope_level += 1
			case .ELSE_IF:
				if scope_level > 0 do continue
				if in_zone do have_entered_zone = true
				in_zone = false if in_zone else !have_entered_zone && get_if_statement_condition(x)
			case .ELSE:
				if scope_level > 0 do continue
				if in_zone do have_entered_zone = true
				in_zone = false if in_zone else true if !have_entered_zone else in_zone
			case .END_IF:
				if scope_level == 0 do return
				scope_level -= 1
			}
		case:
			if in_zone do interpret_line(subline, program)
		}
	}

	error("Program finished without if statement closing!")
}

interpret_while_statement :: proc(stmt: While_Statement, program: Program) {	
	in_zone := get_condition(stmt.condition_tokens)

	starting_line := current_line
	current_line += 1
	scope_level: int
	
	for ; current_line < len(program); current_line += 1 {
		subline := program[current_line]
		
		#partial switch x in subline {
		case While_Statement:
			if in_zone do interpret_while_statement(x, program); else do scope_level += 1
		case Loop_End_Statement:
			defer scope_level -= 1
			if scope_level != 0 do continue
			if !in_zone do return
			current_line = starting_line
			interpret_while_statement(stmt, program)
			return
		case:
			if in_zone do interpret_line(subline, program)
		}
	}

	error("Program finished without while loop closing!")
}

interpret_do_until_statement :: proc(stmt: Do_Until_Statement, program: Program) {
	if stmt.type != .START do error("Unexpected do-until statement of type '%v'!", stmt.type)
	
	starting_line := current_line
	current_line += 1
	
	for ; current_line < len(program); current_line += 1 {
		subline := program[current_line]
		
		#partial switch x in subline {
		case Do_Until_Statement:
			switch x.type {
			case .START:
				interpret_do_until_statement(x, program)
			case .FINISH:
				cond := get_condition(x.condition_tokens)
				if cond do return
				current_line = starting_line
				interpret_do_until_statement(stmt, program)
				return
			}
		case:
			interpret_line(subline, program)
		}
	}

	error("Program finished without do-until loop closing!")
}

interpret_for_statement :: proc(stmt: For_Statement, program: Program) {
	stmt := stmt
	if _, ok := values[stmt.id]; !ok do error("Unknown variable: '%s'", stmt.id)

	current_line += 1
	starting_line := current_line

	from_expr := parse_expression(&stmt.from_value)
	to_expr := parse_expression(&stmt.to_value)
	step_expr: Maybe(Expression) = nil if stmt.step_value == nil else parse_expression(&stmt.step_value.?)

	from := evaluate_expression(from_expr)
	to := evaluate_expression(to_expr)

	if type_of_dt(from) == bool || type_of_dt(to) == bool do error("Expected number in for loop, got boolean!")
	if type_of_dt(from) == string || type_of_dt(to) == string do error("Expected number in for loop, got string!")
	is_float := type_of_dt(from) == f64 || type_of_dt(to) == f64
	
	step := Data_Type(f64(1) if is_float else int(1)) if step_expr == nil else evaluate_expression(step_expr.?)
	if type_of_dt(step) == bool || type_of_dt(step) == string do error("Expected number in step value!")

	assign_value(stmt.id, from)
	for {
		current_line = starting_line
		found_loop_end := false
		loop: for ; current_line < len(program); current_line += 1 {
			subline := program[current_line]
			
			#partial switch x in subline {
			case Loop_End_Statement: 
				found_loop_end = true
				break loop
			case: interpret_line(subline, program)
			}
		}

		if !found_loop_end do error("Program finished without for loop closing!")
		if dt_equal(values[stmt.id].type, to) do break
		assign_value(stmt.id, numeric_operation(values[stmt.id].type, step, "+"))
	}

	for ; current_line < len(program); current_line += 1 {
		subline := program[current_line]
		#partial switch x in subline {
		case Loop_End_Statement: return		
		}
	}
}

interpret_switch_statement :: proc(stmt: Switch_Statement, program: Program) {
	if stmt.type != .START do error("Unexpected switch end statement!")
	current_line += 1
	in_scope: bool
	have_entered_scope: bool
	for ; current_line < len(program); current_line += 1 {
		subline := program[current_line]
		#partial switch v in subline {
		case Switch_Statement:
			if v.type == .START do interpret_switch_statement(v, program)
			if v.type == .FINISH do return
		case Switch_Case_Statement:
			in_scope = interpret_switch_case(stmt.id, v)
			if have_entered_scope {
				if in_scope do in_scope = false
			} else {
				if in_scope do have_entered_scope = true
			}
		case:
			if in_scope do interpret_line(subline, program)
		}
	}

	error("Program finished without switch statement closing!")
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
		case Print_Statement, Read_Statement, If_Statement, While_Statement, Do_Until_Statement,
			For_Statement, Loop_End_Statement, Switch_Statement, Switch_Case_Statement: 
			error("Expected some constant declaration, got %v!", v)
		case Program_Statement:
			if v.type != .START do error("Unexpected program statement!")
			if assignments == 0 do error("Got no constant assignments!")
			break loop
		case Value_Type_Header:
			if v.type == .CONSTANT do error("Duplicate constant header!")
			if assignments == 0 do error("Got no constant assignments!")
			break loop
		case Variable_Init_Statement: error("Expected constant declaraion, not variable!")
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
		case Print_Statement, Read_Statement, If_Statement, While_Statement, Do_Until_Statement, 
			For_Statement, Loop_End_Statement, Switch_Statement, Switch_Case_Statement: 
			error("Expected some constant declaration, got %v!", v)
		case Program_Statement:
			if v.type != .START do error("Unexpected program statement!")
			if reached_type == false do error("Got no variable declarations!")
			break loop
		case Value_Type_Header:
			if v.type == .VARIABLE do error("Duplicate variable header!")
			if reached_type == false do error("Got no variable declarations!")
			break loop
		case Variable_Init_Statement: 
			for var in v.variables {
				#partial switch v.type {
				case .INTEGERS: values[var] = var_of(int(0), false) 
				case .FLOATS: values[var] = var_of(f64(0), false)
				case .STRINGS: values[var] = var_of("", false)
				case .BOOLS: values[var] = var_of(false, false)
				}
			}
			reached_type = true
		}
	}
	current_line -= 1
}

interpret_switch_case :: proc(id: string, stmt: Switch_Case_Statement) -> bool {
	value, ok := get_value(id)
	if !ok do error("Unknown value: '%s'!", value.type)
	if !value.initialized do error("Uninitialized value of type: '%s'!", type_of_dt(value.type))
	stmt := stmt

	for &tokens in stmt.values {
		if len(tokens) == 1 && tokens[0].type == .ELSE do return true
		
		switch v in value.type {
		case bool:
			if len(tokens) != 1 do error("Expected bool literal!")
			if v && tokens[0].type == .BOOL_LITERAL && tokens[0].value == "ΑΛΗΘΗΣ" do return true
			if !v && tokens[0].type == .BOOL_LITERAL && tokens[0].value == "ΨΕΥΔΗΣ" do return true
		case string:
			if len(tokens) != 1 do error("Expected string literal!")
			if v == tokens[0].value do return true
		case int, f64:
			valid_argument: bool
			
			if len(tokens) == 1 {
				valid_argument = true
				val := evaluate_expression(parse_expression(&tokens))
				if dt_equal(value.type, val) do return true
			}
			
			if len(tokens) == 2 && tokens[0].type == .COMPARATIVE_OPERATOR {
				valid_argument = true
				val := evaluate_expression(parse_expression_single(tokens[1]))
				
				switch tokens[0].value {
				case ">", ">=", "<", "<=": 
					if comparative_operation(value.type, val, ">").(bool) do return true
				case: error("Unexpected operator in switch case statement: '%s'!", tokens[0].value)
				}
			}

			if len(tokens) == 3 && tokens[1].type == .RANGE {
				valid_argument = true
				val1 := evaluate_expression(parse_expression_single(tokens[0]))
				val2 := evaluate_expression(parse_expression_single(tokens[2]))
				if comparative_operation(val1, val2, ">=").(bool) do error("Left side of range is bigger or equal to right side!")
				
				in_range := true
				if comparative_operation(value.type, val1, "<").(bool) do in_range = false
				if comparative_operation(value.type, val2, ">").(bool) do in_range = false
				if in_range do return true
			}

			if !valid_argument do error("Invalid argument for number case!")
		}
	}

	return false
}

assign_value :: proc(id: string, value: Data_Type) {
	_, ok := values[id]
	if !ok do error("Unknown value: '%s'!", id)

	if !values[id].variable do error("Cannot assign to a constant!")

	if type_of_dt(values[id].type) == int && type_of_dt(value) == f64 {
		new_int := float_to_int(value.(f64))
		if new_int == nil do error("Cannot assign value '%v' to variable '%s' of type '%v'!", 
			value, id, type_of_dt(values[id].type))
		values[id] = var_of(new_int.(int))
		return
	}

	if type_of_dt(values[id].type) == f64 && type_of_dt(value) == int {
		new_float := f64(value.(int))
		values[id] = var_of(new_float)
		return
	}
	
	if type_of_dt(values[id].type) != type_of_dt(value) do error("Cannot assign value '%v' to variable '%s' of type '%v'!", 
		value, id, type_of_dt(values[id].type))
	
	values[id] = var_of(value)
}

interpret_expression :: proc(line: Line) {
	if !program_started || program_ended do error("Cannot calculate expressions while program isn't running!")
	expr := line.(Expression)
	
	info := is_assignment_expr(expr)
	if info == nil do error("Unhandled expression!")
	
	value := evaluate_expression(info.?.exp^)
	assign_value(info.?.str, value)
}

@(private)
run_program :: proc(program: Program) {
	current_line = 0
	for ; current_line < len(program); current_line += 1 {
		line := program[current_line]
		if current_line == 0 {
			pstmt, pstmt_ok := line.(Program_Statement)
			if !pstmt_ok do error("Expected program name declaration at the start!")
			program_name = pstmt.value
			continue
		}

		interpret_line(line, program)
	}

	if !program_started do error("Nothing to do, program hasn't started!")
	if program_started && !program_ended do error("Program is unfinished!")
	fmt.printf("[Program %s finished succesfully.]\n", program_name)
}

print_data_type :: proc(dt: Data_Type) {
	switch v in dt {
	case int: fmt.printf("%d", v)
	case f64: fmt.printf("%f", v)
	case string: fmt.printf("%s", v)
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
	case f64:
		result, ok := strconv.parse_f64(str)
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

			result_f64, is_float := strconv.parse_f64(str)
			if is_float do return result_f64
			
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
			if type_of_dt(value) == f64 do return -value.(f64)
			error("Cannot negate a non-number!")
		case "+":
			if type_of_dt(value) == int || type_of_dt(value) == f64 do return value
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
	case "/": return f64(lhs.(int)) / f64(rhs.(int))
	case "DIV": return lhs.(int) / rhs.(int)
	case "MOD": return lhs.(int) % rhs.(int)
	case "^":
		result := math.pow(f64(lhs.(int)), f64(rhs.(int)))
		if float_to_int(result) != nil do return int(result)
		return result
	}

	lhs_float := f64(lhs.(int)) if lhs_is_int else lhs.(f64)
	rhs_float := f64(rhs.(int)) if rhs_is_int else rhs.(f64)

	switch op {
	case "+": return lhs_float + rhs_float
	case "-": return lhs_float - rhs_float
	case "*": return lhs_float * rhs_float
	case "/": return lhs_float / rhs_float
	case "DIV":
		lhs_int, rhs_int := float_to_int(lhs_float), float_to_int(rhs_float)
		if lhs_int == nil || rhs_int == nil do error("Cannot perform DIV on floats!")
		return lhs_int.? / rhs_int.?
	case "MOD": 
		lhs_int, rhs_int := float_to_int(lhs_float), float_to_int(rhs_float)
		if lhs_int == nil || rhs_int == nil do error("Cannot perform MOD on floats!")
		return lhs_int.? % rhs_int.?
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

	lhs_float := f64(lhs.(int)) if type_of_dt(lhs) == int else lhs.(f64)
	rhs_float := f64(rhs.(int)) if type_of_dt(rhs) == int else rhs.(f64)

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