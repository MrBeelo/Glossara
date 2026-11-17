package glsr

import "core:fmt"
import "core:os"

main :: proc() {
	args := os.args

	if len(args) < 2 do panic("No input!")

	data, err := os.read_entire_file(args[1], context.allocator)
	if err != nil do fmt.panicf("Error with reading file \"%s\"!", args[1])
	str := string(data)

	values = make(map[string]Value)
	
	lexer := new_lexer(str)
	program := parse_program(lexer)	
	run_program(program)
}