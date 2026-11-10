package glsr

values: map[string]Value

Value :: struct {
	type: Data_Type,
	variable: bool,
	initialized: bool,
}

Data_Type :: union {
	int,
	f32,
	string,
	bool,
}

get_value :: proc(id: string) -> (Value, bool) {
	value, ok := values[id]
	if !ok || !value.initialized do return value, false
	return value, true
}

var_of :: proc(dt: Data_Type, initialized := true) -> Value { return {dt, true, initialized} }
const_of :: proc(dt: Data_Type, initialized := true) -> Value { return {dt, false, initialized} }

type_of_dt :: proc(dt: Data_Type) -> typeid {
	switch v in dt {
	case int: return int
	case f32: return f32
	case bool: return bool
	case string: return string 
	}
	return nil
}

reverse :: proc(arr: ^[dynamic]$T) {
	temp := make([dynamic]T, len(arr))
	for i := 0; i < len(arr); i += 1 do temp[i] = arr[len(arr) - i - 1]
	for i := 0; i < len(arr); i += 1 do arr[i] = temp[i]
	delete(temp)
}