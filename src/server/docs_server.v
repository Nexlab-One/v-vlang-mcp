module server

import os
import json
import regex
import mcp

// PathStatus tracks which paths are available
pub struct PathStatus {
pub mut:
	docs         bool
	examples     bool
	stdlib       bool
	v_ui         bool
	v_ui_examples bool
}

// VDocumentationServer provides V language documentation and examples
pub struct VDocumentationServer {
pub:
	config      ServerConfig
	path_status PathStatus
mut:
	cache       Cache
}

// new_docs_server creates a new documentation server
pub fn new_docs_server(config ServerConfig) VDocumentationServer {
	// Validate paths first
	docs_path := os.join_path(config.v_repo_path, 'doc')
	examples_path := os.join_path(config.v_repo_path, 'examples')
	vlib_path := os.join_path(config.v_repo_path, 'vlib')

	mut path_status := PathStatus{
		docs: os.exists(docs_path) && os.is_dir(docs_path)
		examples: os.exists(examples_path) && os.is_dir(examples_path)
		stdlib: os.exists(vlib_path) && os.is_dir(vlib_path)
		v_ui: false
		v_ui_examples: false
	}

	if config.v_ui_path != '' {
		path_status.v_ui = os.exists(config.v_ui_path) && os.is_dir(config.v_ui_path)
		v_ui_examples := os.join_path(config.v_ui_path, 'examples')
		path_status.v_ui_examples = os.exists(v_ui_examples) && os.is_dir(v_ui_examples)
	}

	return VDocumentationServer{
		config: config
		cache: new_cache(config.cache_ttl_seconds)
		path_status: path_status
	}
}

// read_file_content reads a file and returns its content
fn (s &VDocumentationServer) read_file_content(file_path string) string {
	if !os.exists(file_path) {
		return 'Error: File not found: ${file_path}'
	}
	content := os.read_file(file_path) or {
		return 'Error reading file ${file_path}: ${err}'
	}
	return content
}

// validate_query validates a search query
fn (s &VDocumentationServer) validate_query(query string, min_length int) !string {
	trimmed := query.trim_space()
	if trimmed.len < min_length {
		return error('Query must be at least ${min_length} characters long')
	}
	return trimmed
}

// get_documentation_sections extracts main sections from V documentation
pub fn (mut s VDocumentationServer) get_documentation_sections() string {
	cache_key := 'docs_sections'

	// Try cache first
	if cached := s.cache.get(cache_key) {
		return cached
	}

	docs_file := os.join_path(s.config.v_repo_path, 'doc', 'docs.md')
	if !os.exists(docs_file) {
		result := json.encode({
			'error': 'Documentation file not found'
		})
		s.cache.set(cache_key, result)
		return result
	}

	content := s.read_file_content(docs_file)
	if content.starts_with('Error:') {
		result := json.encode({
			'error': content
		})
		s.cache.set(cache_key, result)
		return result
	}

	// Split by main headers
	mut sections := map[string]string{}
	mut current_section := ''
	mut current_content := []string{}

	lines := content.split('\n')
	for line in lines {
		if line.starts_with('# ') {
			if current_section != '' {
				sections[current_section] = current_content.join('\n')
			}
			current_section = line[2..].trim_space()
			current_content = [line]
		} else if line.starts_with('## ') {
			if current_section != '' {
				sections[current_section] = current_content.join('\n')
			}
			current_section = line[3..].trim_space()
			current_content = [line]
		} else {
			current_content << line
		}
	}

	if current_section != '' {
		sections[current_section] = current_content.join('\n')
	}

	result := json.encode(sections)
	s.cache.set(cache_key, result)
	return result
}

// search_documentation searches V documentation and vlib for a query
pub fn (mut s VDocumentationServer) search_documentation(query string) string {
	validated_query := s.validate_query(query, 2) or {
		return json.encode({
			'error': err.msg()
		})
	}

	mut all_results := []map[string]mcp.JsonAny{}

	// Search documentation file
	docs_file := os.join_path(s.config.v_repo_path, 'doc', 'docs.md')
	if os.exists(docs_file) {
		docs_results_json := s.search_in_file(docs_file, validated_query)
		docs_results := json.decode([]map[string]mcp.JsonAny, docs_results_json) or { []map[string]mcp.JsonAny{} }
		for result in docs_results {
			all_results << result.clone()
		}
	}

	// Search vlib (standard library) if available
	if s.path_status.stdlib {
		vlib_path := os.join_path(s.config.v_repo_path, 'vlib')
		s.search_in_directory(vlib_path, validated_query, mut all_results, s.config.v_repo_path)
	}

	// Sort by score and limit
	if all_results.len > 0 {
		mut result_scores := []f64{len: all_results.len}
		for i, r in all_results {
			score_val := match r['score'] {
				f64 { r['score'] as f64 }
				else { 0.0 }
			}
			result_scores[i] = score_val
		}
		mut result_indices := []int{len: all_results.len, init: index}
		// Sort indices by score descending
		for i := 0; i < result_indices.len; i++ {
			for j := i + 1; j < result_indices.len; j++ {
				if result_scores[result_indices[i]] < result_scores[result_indices[j]] {
					result_indices[i], result_indices[j] = result_indices[j], result_indices[i]
				}
			}
		}
		mut sorted_results := []map[string]mcp.JsonAny{cap: all_results.len}
		for idx in result_indices {
			sorted_results << all_results[idx].clone()
		}
		all_results = sorted_results.clone()
	}

	if all_results.len > s.config.max_search_results {
		all_results = all_results[..s.config.max_search_results].clone()
	}

	if all_results.len == 0 {
		return json.encode([{
			'message': 'No matches found for "${validated_query}"'
		}])
	}

	return json.encode(all_results)
}

// search_in_file searches for a pattern in a file
fn (s &VDocumentationServer) search_in_file(file_path string, pattern string) string {
	content := s.read_file_content(file_path)
	if content.starts_with('Error:') {
		return json.encode([{
			'error': content
		}])
	}

	// Create regex pattern (case-insensitive, escape special chars)
	escaped_pattern := pattern.replace_each(['\\', '\\\\', '.', '\\.', '*', '\\*', '+', '\\+', '?', '\\?', '^', '\\^', '$', '\\$', '[', '\\[', ']', '\\]', '(', '\\(', ')', '\\)', '{', '\\{', '}', '\\}', '|', '\\|'])
	mut re := regex.regex_opt('(?i)${escaped_pattern}') or {
		return json.encode([{
			'error': 'Invalid regex pattern: ${pattern} - ${err}'
		}])
	}

	mut matches := []map[string]mcp.JsonAny{}
	lines := content.split('\n')
	context_lines := 3

	for i, line in lines {
		start, end := re.find(line)
		if start >= 0 && end > start {
			// Get context
			start_line := if i - context_lines >= 0 { i - context_lines } else { 0 }
			mut end_line := if i + context_lines + 1 < lines.len { i + context_lines + 1 } else { lines.len }

			// Look for paragraph boundaries
			mut actual_start := start_line
			for actual_start > 0 && lines[actual_start - 1].trim_space() != '' {
				actual_start--
			}
			mut actual_end := end_line
			for actual_end < lines.len && lines[actual_end].trim_space() != '' {
				actual_end++
			}

			context_lines_list := lines[actual_start..actual_end]
			context := context_lines_list.join('\n').trim_space()

			// Calculate relevance score
			mut score := 1.0
			if line.to_lower().contains(pattern.to_lower()) {
				score += 0.5
			}
			if line.to_lower().starts_with(pattern.to_lower()) {
				score += 0.3
			}
			if context.len > line.len {
				score += 0.2
			}

			// Get relative path
			rel_path := file_path.replace(s.config.v_repo_path + os.path_separator, '')

			matches << {
				'line':    mcp.JsonAny(mcp.JsonAnyInt(i + 1))
				'content': mcp.JsonAny(line.trim_space())
				'context': mcp.JsonAny(context)
				'file':    mcp.JsonAny(rel_path)
				'score':   mcp.JsonAny(f64(score))
				'pattern': mcp.JsonAny(pattern)
			}
		}
	}

	// Sort by score (descending) - create indices and sort them
	if matches.len > 0 {
		mut scores := []f64{len: matches.len}
		for i, m in matches {
			score_val := match m['score'] {
				f64 { m['score'] as f64 }
				else { 0.0 }
			}
			scores[i] = score_val
		}
		mut indices := []int{len: matches.len, init: index}
		// Sort indices by score descending
		for i := 0; i < indices.len; i++ {
			for j := i + 1; j < indices.len; j++ {
				if scores[indices[i]] < scores[indices[j]] {
					indices[i], indices[j] = indices[j], indices[i]
				}
			}
		}
		// Reorder matches array
		mut sorted_matches := []map[string]mcp.JsonAny{cap: matches.len}
		for idx in indices {
			sorted_matches << matches[idx].clone()
		}
		matches = sorted_matches.clone()
	}

	if matches.len > s.config.max_search_results {
		matches = matches[..s.config.max_search_results].clone()
	}

	if matches.len == 0 {
		return json.encode([{
			'message': 'No matches found for "${pattern}"'
		}])
	}

	return json.encode(matches)
}

// get_examples_list returns a list of all V examples
pub fn (mut s VDocumentationServer) get_examples_list() string {
	cache_key := 'examples_list'

	if cached := s.cache.get(cache_key) {
		return cached
	}

	examples_path := os.join_path(s.config.v_repo_path, 'examples')
	if !os.exists(examples_path) || !os.is_dir(examples_path) {
		result := json.encode([{
			'error': 'Examples directory not found'
		}])
		s.cache.set(cache_key, result)
		return result
	}

	mut examples := []map[string]string{}
	s.collect_v_files(examples_path, mut examples, s.config.v_repo_path)

	// Sort by name - create sorted indices and rebuild array
	if examples.len > 0 {
		mut indices := []int{len: examples.len, init: index}
		unsafe {
			for i := 0; i < indices.len; i++ {
				for j := i + 1; j < indices.len; j++ {
					name_i := examples[indices[i]]['name'] or { '' }
					name_j := examples[indices[j]]['name'] or { '' }
					if name_i > name_j {
						indices[i], indices[j] = indices[j], indices[i]
					}
				}
			}
		}
		mut sorted_examples := []map[string]string{cap: examples.len}
		for idx in indices {
			sorted_examples << examples[idx].clone()
		}
		examples = sorted_examples.clone()
	}

	result := json.encode(examples)
	s.cache.set(cache_key, result)
	return result
}

// collect_v_files recursively collects .v files
fn (s &VDocumentationServer) collect_v_files(dir string, mut examples []map[string]string, base_path string) {
	files := os.ls(dir) or { return }
	for file in files {
		file_path := os.join_path(dir, file)
		if os.is_dir(file_path) {
			s.collect_v_files(file_path, mut examples, base_path)
		} else if file.ends_with('.v') {
			name := os.file_name(file_path).replace('.v', '')
			rel_path := file_path.replace(base_path + os.path_separator, '')
			description := s.extract_example_description(file_path)
			examples << {
				'name':        name
				'path':        rel_path
				'description': description
			}
		}
	}
}

// extract_example_description extracts description from example file
fn (s &VDocumentationServer) extract_example_description(file_path string) string {
	content := s.read_file_content(file_path)
	if content.starts_with('Error:') {
		return 'V example'
	}

	lines := content.split('\n')
	for line in lines {
		trimmed := line.trim_space()
		if trimmed.len > 10 && !trimmed.starts_with('//') && !trimmed.starts_with('#') {
			return trimmed
		}
	}
	return 'V example'
}

// get_example_content returns the content of a specific example
pub fn (mut s VDocumentationServer) get_example_content(example_name string) string {
	cache_key := 'example_${example_name}'

	if cached := s.cache.get(cache_key) {
		return cached
	}

	examples_path := os.join_path(s.config.v_repo_path, 'examples')
	if !os.exists(examples_path) || !os.is_dir(examples_path) {
		result := json.encode({
			'error': 'Examples directory not found'
		})
		return result
	}

	// Search for the example file
	found_path := s.find_v_file(examples_path, example_name)

	if found_path == '' {
		result := json.encode({
			'error': 'Example "${example_name}" not found'
		})
		return result
	}

	content := s.read_file_content(found_path)
	rel_path := found_path.replace(s.config.v_repo_path + os.path_separator, '')

	result := json.encode({
		'name':    example_name
		'path':    rel_path
		'content': content
	})
	s.cache.set(cache_key, result)
	return result
}

// find_v_file recursively finds a .v file by name
fn (s &VDocumentationServer) find_v_file(dir string, name string) string {
	files := os.ls(dir) or { return '' }
	for file in files {
		file_path := os.join_path(dir, file)
		if os.is_dir(file_path) {
			result := s.find_v_file(file_path, name)
			if result != '' {
				return result
			}
		} else if file == '${name}.v' {
			return file_path
		}
	}
	return ''
}

// search_examples searches through example code
pub fn (mut s VDocumentationServer) search_examples(query string) string {
	validated_query := s.validate_query(query, 2) or {
		return json.encode([{
			'error': err.msg()
		}])
	}

	examples_path := os.join_path(s.config.v_repo_path, 'examples')
	if !os.exists(examples_path) || !os.is_dir(examples_path) {
		return json.encode([{
			'error': 'Examples directory not found'
		}])
	}

	mut results := []map[string]mcp.JsonAny{}
	s.search_in_directory(examples_path, validated_query, mut results, s.config.v_repo_path)

	// Sort by score and limit
	if results.len > 0 {
		mut result_scores := []f64{len: results.len}
		for i, r in results {
			score_val := match r['score'] {
				f64 { r['score'] as f64 }
				else { 0.0 }
			}
			result_scores[i] = score_val
		}
		mut result_indices := []int{len: results.len, init: index}
		// Sort indices by score descending
		for i := 0; i < result_indices.len; i++ {
			for j := i + 1; j < result_indices.len; j++ {
				if result_scores[result_indices[i]] < result_scores[result_indices[j]] {
					result_indices[i], result_indices[j] = result_indices[j], result_indices[i]
				}
			}
		}
		mut sorted_results := []map[string]mcp.JsonAny{cap: results.len}
		for idx in result_indices {
			sorted_results << results[idx].clone()
		}
		results = sorted_results.clone()
	}

	if results.len > s.config.max_search_results {
		results = results[..s.config.max_search_results].clone()
	}

	if results.len == 0 {
		return json.encode([{
			'message': 'No matches found for "${validated_query}"'
		}])
	}

	return json.encode(results)
}

// search_in_directory recursively searches for pattern in .v files
fn (s &VDocumentationServer) search_in_directory(dir string, pattern string, mut results []map[string]mcp.JsonAny, base_path string) {
	escaped_pattern := pattern.replace_each(['\\', '\\\\', '.', '\\.', '*', '\\*', '+', '\\+', '?', '\\?', '^', '\\^', '$', '\\$', '[', '\\[', ']', '\\]', '(', '\\(', ')', '\\)', '{', '\\{', '}', '\\}', '|', '\\|'])
	mut re := regex.regex_opt('(?i)${escaped_pattern}') or { return }
	files := os.ls(dir) or { return }
	for file in files {
		file_path := os.join_path(dir, file)
		if os.is_dir(file_path) {
			s.search_in_directory(file_path, pattern, mut results, base_path)
		} else if file.ends_with('.v') {
			content := s.read_file_content(file_path)
			if content.starts_with('Error:') {
				continue
			}
			lines := content.split('\n')
			for i, line in lines {
				start, end := re.find(line)
				if start >= 0 && end > start {
					rel_path := file_path.replace(base_path + os.path_separator, '')
					mut score := 1.0
					if line.to_lower().contains(pattern.to_lower()) {
						score += 0.5
					}
					results << {
						'line':    mcp.JsonAny(mcp.JsonAnyInt(i + 1))
						'content': mcp.JsonAny(line.trim_space())
						'file':    mcp.JsonAny(rel_path)
						'score':   mcp.JsonAny(f64(score))
						'pattern': mcp.JsonAny(pattern)
					}
				}
			}
		}
	}
}

// get_stdlib_modules returns a list of standard library modules
pub fn (mut s VDocumentationServer) get_stdlib_modules() string {
	cache_key := 'stdlib_modules'

	if cached := s.cache.get(cache_key) {
		return cached
	}

	vlib_path := os.join_path(s.config.v_repo_path, 'vlib')
	if !os.exists(vlib_path) || !os.is_dir(vlib_path) {
		result := json.encode([{
			'error': 'Standard library directory not found'
		}])
		s.cache.set(cache_key, result)
		return result
	}

	mut modules := []map[string]string{}
	files := os.ls(vlib_path) or {
		result := json.encode([{
			'error': 'Failed to list vlib directory'
		}])
		return result
	}

	for file in files {
		module_path := os.join_path(vlib_path, file)
		if os.is_dir(module_path) && !file.starts_with('.') {
			readme_path := os.join_path(module_path, 'README.md')
			mut description := 'V standard library module'
			if os.exists(readme_path) {
				readme_content := s.read_file_content(readme_path)
				if !readme_content.starts_with('Error:') {
					lines := readme_content.split('\n')
					for line in lines {
						trimmed := line.trim_space()
						if trimmed.len > 10 && !trimmed.starts_with('#') {
							description = trimmed
							break
						}
					}
				}
			}
			rel_path := module_path.replace(s.config.v_repo_path + os.path_separator, '')
			modules << {
				'name':        file
				'path':        rel_path
				'description': description
			}
		}
	}

	// Sort by name - create sorted indices and rebuild array
	if modules.len > 0 {
		mut indices := []int{len: modules.len, init: index}
		unsafe {
			for i := 0; i < indices.len; i++ {
				for j := i + 1; j < indices.len; j++ {
					name_i := modules[indices[i]]['name'] or { '' }
					name_j := modules[indices[j]]['name'] or { '' }
					if name_i > name_j {
						indices[i], indices[j] = indices[j], indices[i]
					}
				}
			}
		}
		mut sorted_modules := []map[string]string{cap: modules.len}
		for idx in indices {
			sorted_modules << modules[idx].clone()
		}
		modules = sorted_modules.clone()
	}

	result := json.encode(modules)
	s.cache.set(cache_key, result)
	return result
}

// get_module_info returns information about a specific module
pub fn (mut s VDocumentationServer) get_module_info(module_name string) string {
	module_path := os.join_path(s.config.v_repo_path, 'vlib', module_name)
	if !os.exists(module_path) || !os.is_dir(module_path) {
		return json.encode({
			'error': 'Module "${module_name}" not found'
		})
	}

	mut info := map[string]mcp.JsonAny{}
	info['name'] = mcp.JsonAny(module_name)

	// Get README if available
	readme_path := os.join_path(module_path, 'README.md')
	if os.exists(readme_path) {
		readme_content := s.read_file_content(readme_path)
		if !readme_content.starts_with('Error:') {
			info['readme'] = mcp.JsonAny(readme_content)
		}
	}

	// List V files in the module
	mut v_files := []map[string]mcp.JsonAny{}
	files := os.ls(module_path) or { return json.encode(info) }
	for file in files {
		file_path := os.join_path(module_path, file)
		if !os.is_dir(file_path) && file.ends_with('.v') {
			file_size := os.file_size(file_path)
			rel_path := file_path.replace(s.config.v_repo_path + os.path_separator, '')
			v_files << {
				'name': mcp.JsonAny(file)
				'path': mcp.JsonAny(rel_path)
				'size': mcp.JsonAny(mcp.JsonAnyInt(int(file_size)))
			}
		}
	}
	// Convert v_files to JsonValue array - v_files is already []map[string]mcp.JsonAny
	// which is compatible with []JsonValue since map[string]JsonValue is part of JsonValue sumtype
	mut files_json := []mcp.JsonAny{}
	for file_info in v_files {
		files_json << mcp.JsonAny(file_info)
	}
	info['files'] = mcp.JsonAny(files_json)

	return json.encode(info)
}

// get_v_ui_examples_list returns a list of V UI examples
pub fn (mut s VDocumentationServer) get_v_ui_examples_list() string {
	cache_key := 'v_ui_examples_list'

	if cached := s.cache.get(cache_key) {
		return cached
	}

	if s.config.v_ui_path == '' || !s.path_status.v_ui_examples {
		result := json.encode([{
			'error': 'V UI examples directory not found'
		}])
		s.cache.set(cache_key, result)
		return result
	}

	v_ui_examples_path := os.join_path(s.config.v_ui_path, 'examples')
	mut examples := []map[string]string{}
	s.collect_v_files(v_ui_examples_path, mut examples, s.config.v_ui_path)

	// Sort by name - create sorted indices and rebuild array
	if examples.len > 0 {
		mut indices := []int{len: examples.len, init: index}
		unsafe {
			for i := 0; i < indices.len; i++ {
				for j := i + 1; j < indices.len; j++ {
					name_i := examples[indices[i]]['name'] or { '' }
					name_j := examples[indices[j]]['name'] or { '' }
					if name_i > name_j {
						indices[i], indices[j] = indices[j], indices[i]
					}
				}
			}
		}
		mut sorted_examples := []map[string]string{cap: examples.len}
		for idx in indices {
			sorted_examples << examples[idx].clone()
		}
		examples = sorted_examples.clone()
	}

	result := json.encode(examples)
	s.cache.set(cache_key, result)
	return result
}

// get_v_ui_example_content returns the content of a specific V UI example
pub fn (mut s VDocumentationServer) get_v_ui_example_content(example_name string) string {
	cache_key := 'v_ui_example_${example_name}'

	if cached := s.cache.get(cache_key) {
		return cached
	}

	if s.config.v_ui_path == '' || !s.path_status.v_ui_examples {
		result := json.encode({
			'error': 'V UI examples directory not found'
		})
		return result
	}

	v_ui_examples_path := os.join_path(s.config.v_ui_path, 'examples')
	found_path := s.find_v_file(v_ui_examples_path, example_name)

	if found_path == '' {
		result := json.encode({
			'error': 'V UI example "${example_name}" not found'
		})
		return result
	}

	content := s.read_file_content(found_path)
	rel_path := found_path.replace(s.config.v_ui_path + os.path_separator, '')

	result := json.encode({
		'name':    example_name
		'path':    rel_path
		'content': content
	})
	s.cache.set(cache_key, result)
	return result
}

// search_v_ui_examples searches through V UI examples
pub fn (mut s VDocumentationServer) search_v_ui_examples(query string) string {
	validated_query := s.validate_query(query, 2) or {
		return json.encode([{
			'error': err.msg()
		}])
	}

	if s.config.v_ui_path == '' || !s.path_status.v_ui_examples {
		return json.encode([{
			'error': 'V UI examples directory not found'
		}])
	}

	v_ui_examples_path := os.join_path(s.config.v_ui_path, 'examples')
	mut results := []map[string]mcp.JsonAny{}
	s.search_in_directory(v_ui_examples_path, validated_query, mut results, s.config.v_ui_path)

	// Sort by score and limit
	if results.len > 0 {
		mut vui_scores := []f64{len: results.len}
		for i, r in results {
			score_val := match r['score'] {
				f64 { r['score'] as f64 }
				else { 0.0 }
			}
			vui_scores[i] = score_val
		}
		mut vui_indices := []int{len: results.len, init: index}
		// Sort indices by score descending
		for i := 0; i < vui_indices.len; i++ {
			for j := i + 1; j < vui_indices.len; j++ {
				if vui_scores[vui_indices[i]] < vui_scores[vui_indices[j]] {
					vui_indices[i], vui_indices[j] = vui_indices[j], vui_indices[i]
				}
			}
		}
		mut sorted_vui_results := []map[string]mcp.JsonAny{cap: results.len}
		for idx in vui_indices {
			sorted_vui_results << results[idx].clone()
		}
		results = sorted_vui_results.clone()
	}

	if results.len > s.config.max_search_results {
		results = results[..s.config.max_search_results].clone()
	}

	if results.len == 0 {
		return json.encode([{
			'message': 'No matches found for "${validated_query}"'
		}])
	}

	return json.encode(results)
}

// clear_cache clears all cache entries
pub fn (mut s VDocumentationServer) clear_cache() string {
	cache_size := s.cache.size()
	s.cache.clear()
	// Return result as map with mixed types - encode manually
	mut result_map := map[string]mcp.JsonAny{}
	result_map['cleared_entries'] = mcp.JsonAny(mcp.JsonAnyInt(cache_size))
	result_map['cleared_timestamps'] = mcp.JsonAny(mcp.JsonAnyInt(cache_size))
	result_map['message'] = mcp.JsonAny('Cleared ${cache_size} cache entries')
	return json.encode(result_map)
}

// get_cache_stats returns cache statistics
pub fn (s &VDocumentationServer) get_cache_stats() map[string]int {
	return {
		'entries':     s.cache.size()
		'ttl_seconds': s.config.cache_ttl_seconds
	}
}
