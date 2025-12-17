module server

import time

// CacheEntry holds a cached value with its timestamp
struct CacheEntry {
	value     string
	timestamp i64
}

// Cache provides TTL-based caching
pub struct Cache {
mut:
	entries map[string]CacheEntry
	ttl     int // Time-to-live in seconds
}

// new_cache creates a new cache with the specified TTL
pub fn new_cache(ttl_seconds int) Cache {
	return Cache{
		entries: map[string]CacheEntry{}
		ttl: ttl_seconds
	}
}

// get retrieves a value from cache if it exists and hasn't expired
pub fn (mut c Cache) get(key string) ?string {
	if key !in c.entries {
		return none
	}

	entry := c.entries[key]
	now := time.now().unix()
	age := now - entry.timestamp

	if age >= c.ttl {
		// Entry expired, remove it
		c.entries.delete(key)
		return none
	}

	return entry.value
}

// set stores a value in cache with current timestamp
pub fn (mut c Cache) set(key string, value string) {
	c.entries[key] = CacheEntry{
		value: value
		timestamp: time.now().unix()
	}
}

// clear removes all entries from cache
pub fn (mut c Cache) clear() {
	c.entries.clear()
}

// clear_expired removes all expired entries
pub fn (mut c Cache) clear_expired() {
	now := time.now().unix()
	mut to_remove := []string{}
	for key, entry in c.entries {
		age := now - entry.timestamp
		if age >= c.ttl {
			to_remove << key
		}
	}
	for key in to_remove {
		c.entries.delete(key)
	}
}

// size returns the number of entries in cache
pub fn (c &Cache) size() int {
	return c.entries.len
}
