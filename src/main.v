module main

import mcp
import server
import tools

fn main() {
	// Load configuration
	config := server.from_env()

	// Create documentation server
	mut docs_server := server.new_docs_server(config)

	// Create tool registry
	tool_registry := tools.new_tool_registry()

	// Log startup
	mcp.log('INFO', 'Starting V MCP Server...')
	mcp.log('INFO', 'V Repo Path: ${config.v_repo_path}')
	if config.v_ui_path != '' {
		mcp.log('INFO', 'V UI Path: ${config.v_ui_path}')
	}

	// Main stdio loop
	for {
		// Read JSON-RPC message from stdin
		json_str := mcp.read_message() or {
			// EOF or error - exit gracefully
			if err.msg() == 'EOF' {
				break
			}
			mcp.log('ERROR', 'Failed to read message: ${err}')
			continue
		}

		// Parse JSON-RPC request
		request := mcp.parse_request(json_str) or {
			// Invalid request - send parse error
			error_response := mcp.create_error_response(
				mcp.JsonAny(mcp.JsonNull{}),
				mcp.parse_error_code,
				'Parse error: ${err}',
				mcp.JsonAny(mcp.JsonNull{})
			)
			response_json := mcp.encode_response(error_response) or {
				mcp.log('ERROR', 'Failed to encode error response: ${err}')
				continue
			}
			mcp.write_message(response_json) or {
				mcp.log('ERROR', 'Failed to write error response: ${err}')
			}
			continue
		}

		// Handle the request
		mut response := mcp.JsonRpcResponse{}
		
		// Route to appropriate tool handler
		result := tool_registry.call_tool(request.method, request.params, mut docs_server) or {
			// Method not found
			response = mcp.create_error_response(
				request.id,
				mcp.method_not_found_code,
				'Method not found: ${request.method}',
				mcp.JsonAny(err.msg())
			)
			response_json := mcp.encode_response(response) or {
				mcp.log('ERROR', 'Failed to encode error response: ${err}')
				continue
			}
			mcp.write_message(response_json) or {
				mcp.log('ERROR', 'Failed to write error response: ${err}')
			}
			continue
		}

		// Create success response
		response = mcp.create_response(
			request.id,
			mcp.JsonAny(result)
		)

		// Encode and send response
		response_json := mcp.encode_response(response) or {
			mcp.log('ERROR', 'Failed to encode response: ${err}')
			// Send internal error
			error_response := mcp.create_error_response(
				request.id,
				mcp.internal_error_code,
				'Failed to encode response: ${err}',
				mcp.JsonAny(mcp.JsonNull{})
			)
			error_json := mcp.encode_response(error_response) or {
				mcp.log('ERROR', 'Failed to encode error response: ${err}')
				continue
			}
			mcp.write_message(error_json) or {
				mcp.log('ERROR', 'Failed to write error response: ${err}')
			}
			continue
		}

		mcp.write_message(response_json) or {
			mcp.log('ERROR', 'Failed to write response: ${err}')
		}
	}

	mcp.log('INFO', 'V MCP Server shutting down')
}
