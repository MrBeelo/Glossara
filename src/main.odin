package glsr

import "core:fmt"
import "core:os"
import "core:unicode/utf8"

// Απλός διερμηνευτής της ΓΛΩΣΣΑΣ.

main :: proc() {
	args := os.args

	if len(args) < 2 do panic("No input!")

	data, err := os.read_entire_file(args[1], context.allocator)
	if err != nil do fmt.panicf("Error with reading file \"%s\"!", args[1])
	str := string(data)
	
	tokens := tokenize(str)
	for token in tokens do fmt.printf("[%v, '%s', %d]\n", token.type, token.value, token.start_pos)
}

error :: proc(stage: enum{LEXER, PARSER}, message: string, args: ..any) -> ! {
	fmt.printf("[%v] %s [pos=%v]\n", stage, fmt.ctprintf(message, ..args), char_pos )
	panic("Interpreter encountered an error!")
}