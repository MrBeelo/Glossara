package glsr

import "core:fmt"
import "core:os"

main :: proc() {
	args := os.args

	if len(args) < 2 do panic("No input!")

	data, err := os.read_entire_file(args[1], context.allocator)
	if err != nil do fmt.panicf("Error with reading file \"%s\"!", args[1])
	str := string(data)
	
	lexer := new_lexer(str)
	expr := parse_expression(lexer)
	fmt.printf("%v\n", expr)
}

error :: proc(stage: enum{LEXER, PARSER}, message: string, args: ..any) -> ! {
	fmt.printf("[%v] %s [%v]\n", stage, fmt.ctprintf(message, ..args), dynamic_start_pos )
	panic("Interpreter encountered an error!")
}