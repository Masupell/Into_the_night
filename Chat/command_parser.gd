class_name CommandParser
extends RefCounted

## main_command { sub_command1 <name:type|opt1,opt2> | sub_command2 [<name:int>] }
##
##   name                 - required fixed word, written without <>
##   <name>               - any string argument
##   <name:type>          - typed argument (int, float, any)
##   <name:type|a,b>      - typed argument restricted to a fixed set of options
##   [<name>]             - optional argument
##   { a | b }            - branches; expands into one line per option
##
## Space- and case-sensitive at the moment

static func tokenize(pattern: String) -> Array[String]:
	var tokens: Array[String] = []
	for token in pattern.split(" ", false):
		tokens.append(token)
	return tokens

static func expand_branches(tokens: Array[String]) -> Array:
	var segments := _split_into_segments(tokens)
	return _cartesian_product(segments)

static func _split_into_segments(tokens: Array[String]) -> Array:
	var segments: Array = []
	var i := 0
	while i < tokens.size():
		var token := tokens[i]
		if token == "{":
			var extracted := _extract_group(tokens, i)
			var group_tokens: Array[String] = extracted[0]
			var group_end: int = extracted[1]

			var expanded: Array = []
			for alt in _split_top_level(group_tokens, "|"):
				expanded.append_array(expand_branches(alt))
			segments.append(expanded)

			i = group_end + 1
		else:
			segments.append([[token]])
			i += 1
	return segments

static func _extract_group(tokens: Array[String], start: int) -> Array:
	var depth := 1
	var group: Array[String] = []
	var i := start + 1
	while i < tokens.size() and depth > 0:
		if tokens[i] == "{":
			depth += 1
		elif tokens[i] == "}":
			depth -= 1
			if depth == 0:
				break
		group.append(tokens[i])
		i += 1
	return [group, i]

static func _split_top_level(tokens: Array[String], separator: String) -> Array:
	var result: Array = []
	var current: Array[String] = []
	var depth := 0
	for token in tokens:
		if token == "{":
			depth += 1
		elif token == "}":
			depth -= 1
		if token == separator and depth == 0:
			result.append(current)
			current = []
		else:
			current.append(token)
	result.append(current)
	return result

static func _cartesian_product(segments: Array) -> Array:
	var results: Array = [[]]
	for segment in segments:
		var next_results: Array = []
		for prefix in results:
			for alternative in segment:
				var combined: Array = prefix.duplicate()
				combined.append_array(alternative)
				next_results.append(combined)
		results = next_results
	return results
