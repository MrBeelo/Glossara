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