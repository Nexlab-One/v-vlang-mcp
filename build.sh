#!/bin/bash
# Build script for V MCP Server

set -e

echo "Building V MCP Server..."

# Build the server
# Use ./src/main.v to avoid module path prefix issues
v -o v-mcp-server ./src/main.v

echo "Build complete! Binary: ./v-mcp-server"
echo ""
echo "Usage:"
echo "  V_REPO_PATH=/path/to/v ./v-mcp-server"

