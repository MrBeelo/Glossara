package glsr

import "core:math"

values: map[string]Value

Value :: struct {
	type: Data_Type,
	variable: bool,
	initialized: bool,
}

Data_Type :: union {
	int,
	f64,
	string,
	bool,
}

dt_equal :: proc(d1, d2: Data_Type) -> bool {
	if type_of_dt(d1) == int && type_of_dt(d2) == f64 {
		new_int := float_to_int(d2.(f64))
		if new_int == nil do return false
		return d1.(int) == new_int
	}

	if type_of_dt(d1) == f64 && type_of_dt(d2) == int {
		new_int := float_to_int(d1.(f64))
		if new_int == nil do return false
		return d2.(int) == new_int
	}

	if type_of_dt(d1) == f64 && type_of_dt(d2) == f64 {
		epsilon :: 0.0000000000001
		return math.abs(d1.(f64) - d2.(f64)) <= epsilon
	}
	
	return d1 == d2
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
	case f64: return f64
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

float_to_int :: proc(float: f64) -> Maybe(int) {
	epsilon :: 0.0000000000001
	rounded_float := f64(int(float))
	if math.abs(float - rounded_float) > epsilon do return nil
	return int(float)
}