module server

import os

// ServerConfig holds configuration for the V MCP Server
pub struct ServerConfig {
pub:
	v_repo_path      string
	v_ui_path        string = ''
	cache_ttl_seconds int = 300
	max_search_results int = 50
	log_level        string = 'INFO'
}

// from_env creates a ServerConfig from environment variables
pub fn from_env() ServerConfig {
	// V repository path
	mut v_repo_path := os.getenv('V_REPO_PATH')
	if v_repo_path == '' {
		// Default to parent directory (assuming we're in v-mcp-server-v/)
		// Get current executable directory and go up one level
		exec_path := os.executable()
		exec_dir := os.dir(exec_path)
		v_repo_path = os.join_path(os.dir(exec_dir), '')
		// If that doesn't work, try current working directory's parent
		if !os.exists(v_repo_path) || !os.is_dir(v_repo_path) {
			cwd := os.getwd()
			v_repo_path = os.dir(cwd)
		}
	}

	// V UI repository path (optional)
	mut v_ui_path := os.getenv('V_UI_PATH')
	if v_ui_path == '' {
		// Default to v-ui submodule in parent directory
		v_ui_path = os.join_path(v_repo_path, 'v-ui')
		if !os.exists(v_ui_path) || !os.is_dir(v_ui_path) {
			v_ui_path = ''
		}
	}

	// Cache TTL
	cache_ttl := os.getenv('V_CACHE_TTL_SECONDS')
	mut cache_ttl_seconds := 300
	if cache_ttl != '' {
		cache_ttl_seconds = cache_ttl.int()
	}

	// Max search results
	max_results := os.getenv('V_MAX_SEARCH_RESULTS')
	mut max_search_results := 50
	if max_results != '' {
		max_search_results = max_results.int()
	}

	// Log level
	log_level := os.getenv('V_LOG_LEVEL')
	mut log_level_str := 'INFO'
	if log_level != '' {
		log_level_str = log_level.to_upper()
	}

	return ServerConfig{
		v_repo_path: v_repo_path
		v_ui_path: v_ui_path
		cache_ttl_seconds: cache_ttl_seconds
		max_search_results: max_search_results
		log_level: log_level_str
	}
}
