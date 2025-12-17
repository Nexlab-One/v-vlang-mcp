module mcp

import os
import json

// JSON-RPC 2.0 message types

// JsonAny is a simplified type for dynamic JSON values
// Use alias for int to avoid JSON decoding conflict with f64
pub type JsonAnyInt = int
// JsonNull represents JSON null
pub struct JsonNull {}

// json_null is a constant instance (wrapped in JsonAny)
pub const json_null = JsonAny(JsonNull{})

pub type JsonAny = bool | f64 | JsonAnyInt | string | []JsonAny | map[string]JsonAny | JsonNull

// JsonRpcRequest represents a JSON-RPC 2.0 request
pub struct JsonRpcRequest {
pub:
	jsonrpc string = '2.0'
	id      JsonAny
	method  string
	params  JsonAny
}

// JsonRpcResponse represents a JSON-RPC 2.0 response
pub struct JsonRpcResponse {
	jsonrpc string = '2.0'
	id      JsonAny
mut:
	result JsonAny
	error  ?JsonRpcError
}

// JsonRpcError represents a JSON-RPC 2.0 error
pub struct JsonRpcError {
	code    int
	message string
	data    JsonAny = json_null
}

// JSON-RPC 2.0 error codes
pub const parse_error_code = -32700 // Invalid JSON was received
pub const invalid_request_code = -32600 // The JSON sent is not a valid Request object
pub const method_not_found_code = -32601 // The method does not exist / is not available
pub const invalid_params_code = -32602 // Invalid method parameter(s)
pub const internal_error_code = -32603 // Internal JSON-RPC error

// Transport functions

// read_message reads a newline-delimited JSON message from stdin
pub fn read_message() !string {
	line := os.get_line()
	if line.len == 0 {
		return error('EOF')
	}
	return line.trim_space()
}

// write_message writes a JSON-RPC message to stdout
pub fn write_message(message string) ! {
	mut stdout := os.stdout()
	stdout.write_string(message + '\n') or {
		// Fallback to print if file write fails
		print(message + '\n')
		return
	}
	os.flush()
}

// write_error writes an error message to stderr
pub fn write_error(message string) {
	eprintln(message)
}

// log writes a log message to stderr
pub fn log(level string, message string) {
	write_error('[${level}] ${message}')
}

// Protocol functions

// parse_request parses a JSON-RPC request from a JSON string
pub fn parse_request(json_str string) !JsonRpcRequest {
	// Use standard json module for dynamic parsing
	raw := json.decode(map[string]JsonAny, json_str)!

	// Validate jsonrpc version
	jsonrpc_any := raw['jsonrpc'] or { return error('Missing jsonrpc field') }
	jsonrpc := match jsonrpc_any {
		string { jsonrpc_any }
		else { return error('Invalid jsonrpc type') }
	}
	if jsonrpc != '2.0' {
		return error('Invalid jsonrpc version')
	}

	// Get method
	method_any := raw['method'] or { return error('Missing method field') }
	method := match method_any {
		string { method_any }
		else { return error('Invalid method type') }
	}

	// Get id (can be string, number, or null)
	id_any := raw['id'] or { json_null }

	// Get params (optional)
	params_any := raw['params'] or { json_null }

	return JsonRpcRequest{
		jsonrpc: '2.0'
		id: id_any
		method: method
		params: params_any
	}
}

// create_response creates a JSON-RPC response
pub fn create_response(id JsonAny, result JsonAny) JsonRpcResponse {
	return JsonRpcResponse{
		jsonrpc: '2.0'
		id: id
		result: result
		error: none
	}
}

// create_error_response creates a JSON-RPC error response
pub fn create_error_response(id JsonAny, code int, message string, data JsonAny) JsonRpcResponse {
	return JsonRpcResponse{
		jsonrpc: '2.0'
		id: id
		result: json_null
		error: JsonRpcError{
			code: code
			message: message
			data: data
		}
	}
}

// encode_response encodes a response to JSON string
pub fn encode_response(response JsonRpcResponse) !string {
	// Use standard json module for encoding
	return json.encode(response)
}

// extract_string_param extracts a string parameter from params
pub fn extract_string_param(params JsonAny, key string) ?string {
	match params {
		map[string]JsonAny {
			val := params[key] or { return none }
			match val {
				string { return val }
				else { return none }
			}
		}
		else { return none }
	}
}

// extract_optional_string_param extracts an optional string parameter
pub fn extract_optional_string_param(params JsonAny, key string) ?string {
	match params {
		map[string]JsonAny {
			if key !in params {
				return none
			}
			val := params[key] or { return none }
			match val {
				string { return val }
				JsonNull { return none }
				else { return none }
			}
		}
		else { return none }
	}
}
