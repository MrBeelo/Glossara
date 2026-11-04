package glsr

Data_Type :: union {
	int,
	f32,
	string,
	bool,
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

reverse :: proc(arr: ^[dynamic]$T) {
	temp := make([dynamic]T, len(arr))
	for i := 0; i < len(arr); i += 1 do temp[i] = arr[len(arr) - i - 1]
	for i := 0; i < len(arr); i += 1 do arr[i] = temp[i]
	delete(temp)
}