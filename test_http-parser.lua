
local ffi = require "ffi"
local bit = require "bit"
local band = bit.band

http_parser = require "http_parser_ffi"

--[[
int http_parser_parse_url(const char *buf, size_t buflen,
                          int is_connect,
                          struct http_parser_url *u);
--]]

--[[
/* Result structure for http_parser_parse_url().
 *
 * Callers should index into field_data[] with UF_* values iff field_set
 * has the relevant (1 << UF_*) bit set. As a courtesy to clients (and
 * because we probably have padding left over), we convert any port to
 * a uint16_t.
 */
struct http_parser_url {
  uint16_t field_set;           /* Bitmask of (1 << UF_*) values */
  uint16_t port;                /* Converted UF_PORT string */

  struct {
    uint16_t off;               /* Offset into buffer in which field starts */
    uint16_t len;               /* Length of run in buffer */
  } field_data[UF_MAX];
};
--]]

local function lstringdup(lstring)
	local len = string.len(lstring)
	local buf = ffi.new("char[?]", len+1)

	ffi.copy(buf, ffi.cast("char *", lstring), len)
	buf[len] = 0;

	return buf, len;
end

function isbitset(value, bit)
	return band(value, 2^bit) > 0
end

function test_parse_url_raw()
	local url,len = lstringdup("udp://192.168.1.1:80/")
	--local url,len = lstringdup("http://www.gooly.com:8081/foo/bar/baz/file.html?filename=santaclaws")
	--local url,len = lstringdup("http://www.microsoft.com:90/foo.html")
	--local url,len = lstringdup("hostname:443")


	local u = ffi.new("struct http_parser_url")

	local res = http_parser_parse_url(url, len, false, u);

	print("result: ", res);

	if true then
		print("port: ", u.port);
		for i = 0,UF_FRAGMENT do
			local havefield = isbitset(u.field_set, i)
			if havefield then
				local offset = u.field_data[i].off
				local len = u.field_data[i].len
				local str = ffi.string(url+offset, len)
				print(i, str)
			else
				print(i, "nil")
			end
		end
	end

end

function test_parse_url()
	local url = "http://www.gooly.com:8081/foo/bar/baz/file.html?filename=santaclaws"
	local values = parseurl(url)

	print("==== URL ====")
	for k,v in pairs(values) do
		print(k,v);
	end
end

require "strtoul"

function test_strtol()
	local str,len = lstringdup("12345");

	local val = strtol(str, nil, 10)

	print(val)
end


test_parse_url_raw();

--test_parse_url();

--test_strtol();
