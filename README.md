# V Language MCP Server

A Model Context Protocol (MCP) server written in V that provides comprehensive access to V programming language documentation, examples, standard library modules, and V UI examples.

## Overview

This MCP server enables AI assistants and other tools to access V language resources through a standardized protocol. It provides tools for searching documentation, browsing examples, exploring the standard library, and accessing V UI examples.

## Features

- **Documentation Access**: Browse and search V language documentation
- **Code Examples**: List, retrieve, and search through V code examples
- **Standard Library**: Explore V standard library modules with detailed information
- **V UI Examples**: Access V UI framework examples (when v-ui submodule is available)
- **Syntax Reference**: Quick reference and detailed explanations of V language features
- **Caching**: Built-in caching system for improved performance
- **Search**: Full-text search across documentation and examples

## Requirements

- [V programming language](https://vlang.io) installed
- V repository cloned (for documentation and examples)
- Optional: v-ui submodule (for V UI examples)

## Building

```bash
v build src/main.v -o v-mcp-server
```

Or simply:

```bash
v src/main.v
```

## Configuration

The server is configured via environment variables:

### Required

- `V_REPO_PATH`: Path to the V repository root directory
  - Default: Attempts to auto-detect from parent directory

### Optional

- `V_UI_PATH`: Path to the v-ui repository (for V UI examples)
  - Default: `$V_REPO_PATH/v-ui` (if exists)
- `V_CACHE_TTL_SECONDS`: Cache time-to-live in seconds
  - Default: `300` (5 minutes)
- `V_MAX_SEARCH_RESULTS`: Maximum number of search results to return
  - Default: `50`
- `V_LOG_LEVEL`: Logging level (INFO, DEBUG, ERROR, etc.)
  - Default: `INFO`

### Example Configuration

```bash
export V_REPO_PATH=/path/to/v
export V_UI_PATH=/path/to/v-ui
export V_CACHE_TTL_SECONDS=600
export V_MAX_SEARCH_RESULTS=100
```

## Usage

The server communicates via JSON-RPC 2.0 over stdio. It reads requests from stdin and writes responses to stdout.

### Running the Server

```bash
./v-mcp-server
```

Or with environment variables:

```bash
V_REPO_PATH=/path/to/v ./v-mcp-server
```

## Available Tools

### Documentation Tools

- `get_v_documentation([section])` - Get V documentation, optionally for a specific section
- `search_v_docs(query)` - Search through V documentation

### Code Examples

- `list_v_examples()` - List all available V code examples
- `get_v_example(name)` - Get complete source code for a specific example
- `search_v_examples(query)` - Search through example code

### Standard Library

- `list_v_stdlib_modules()` - List all V standard library modules
- `get_v_module_info(module_name)` - Get detailed info about a specific module

### V UI Examples

- `list_v_ui_examples()` - List all available V UI code examples
- `get_v_ui_example(name)` - Get complete source code for a specific V UI example
- `search_v_ui_examples(query)` - Search through V UI example code

### Language Reference

- `explain_v_syntax(feature)` - Explain V language features (variables, arrays, structs, functions, control_flow, modules, error_handling, concurrency)
- `get_v_quick_reference()` - Get quick V syntax reference

### Configuration & Cache

- `get_v_config()` - Show current server configuration and cache statistics
- `clear_v_cache()` - Clear cached content for fresh results

### Help

- `get_v_help()` - Show help information

## Project Structure

```
.
├── src/
│   ├── main.v              # Entry point and JSON-RPC message loop
│   ├── mcp/
│   │   └── mcp.v          # JSON-RPC 2.0 protocol implementation
│   ├── server/
│   │   ├── cache.v        # TTL-based caching system
│   │   ├── config.v       # Configuration management
│   │   └── docs_server.v  # Documentation server implementation
│   └── tools/
│       └── tools.v        # Tool registry and handlers
├── v.mod                   # V module definition
└── README.md              # This file
```

## Architecture

The server follows a modular architecture:

- **mcp**: JSON-RPC 2.0 protocol handling
- **server**: Core server functionality including caching, configuration, and documentation access
- **tools**: Tool registry and individual tool handlers
- **main**: Entry point that orchestrates the message loop

## Caching

The server implements a TTL-based caching system to improve performance:

- Cache entries expire after the configured TTL (default: 5 minutes)
- Cached data includes documentation sections, example lists, and module information
- Use `clear_v_cache()` to force a refresh of cached content

## Error Handling

The server implements proper JSON-RPC 2.0 error handling:

- Parse errors for invalid JSON
- Invalid request errors for malformed requests
- Method not found errors for unknown tools
- Invalid params errors for incorrect parameters
- Internal errors for server-side issues

## Integration

This server is designed to be used as a submodule in the main V MCP repository. It provides V-specific functionality while the parent repository handles MCP server management and orchestration.

## Development

### Module Structure

The code is organized into modules:

- `main` - Entry point
- `mcp` - JSON-RPC protocol
- `server` - Server functionality
- `tools` - Tool handlers

### Adding New Tools

1. Add a handler function in `src/tools/tools.v`
2. Register the handler in `register_all()` method
3. Implement the tool logic using the `VDocumentationServer` API

## License

This project is part of the V MCP ecosystem. See the parent repository for license information.

## Contributing

This is a submodule of the main V MCP repository. Contributions should be made through the parent repository's contribution process.

