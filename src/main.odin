package glsr

import "core:fmt"
import "core:os"

vars: map[string]Data_Type

main :: proc() {
	args := os.args

	if len(args) < 2 do panic("No input!")

	data, err := os.read_entire_file(args[1], context.allocator)
	if err != nil do fmt.panicf("Error with reading file \"%s\"!", args[1])
	str := string(data)

	vars := new(map[string]Data_Type)
	
	lexer := new_lexer(str)
	expr := parse_expression(lexer)
	
	if info := is_assignment_expr(expr); info != nil {
		value := evaluate_expression(info.?.exp^)
		vars[info.?.str] = value
		fmt.printf("Saved value %v to variable %s with type %v\n", value, info.?.str, type_of_dt(value))
	} else {
		value := evaluate_expression(expr)
		fmt.printf("%v\n", value)
	}
}