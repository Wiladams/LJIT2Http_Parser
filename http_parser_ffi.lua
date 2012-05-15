--[[
This is a LuaJIT to http-parser FFI interface file.

This file originated from the Joyent http-parser project, which had the following
copyright:

/* Copyright Joyent, Inc. and other Node contributors. All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */
--]]

local ffi = require "ffi"
local bit = require "bit"
local band = bit.band

HTTP_PARSER_VERSION_MAJOR = 1
HTTP_PARSER_VERSION_MINOR = 0


-- Maximium header size allowed
HTTP_MAX_HEADER_SIZE = (80*1024)

ffi.cdef[[
typedef struct http_parser http_parser;
typedef struct http_parser_settings http_parser_settings;


/* Callbacks should return non-zero to indicate an error. The parser will
 * then halt execution.
 *
 * The one exception is on_headers_complete. In a HTTP_RESPONSE parser
 * returning '1' from on_headers_complete will tell the parser that it
 * should not expect a body. This is used when receiving a response to a
 * HEAD request which may contain 'Content-Length' or 'Transfer-Encoding:
 * chunked' headers that indicate the presence of a body.
 *
 * http_data_cb does not return data chunks. It will be call arbitrarally
 * many times for each string. E.G. you might get 10 callbacks for "on_path"
 * each providing just a few characters more data.
 */
typedef int (*http_data_cb) (http_parser*, const char *at, size_t length);
typedef int (*http_cb) (http_parser*);
]]




HTTP_METHODS = {
	DELETE 		= {0,      "DELETE"};
	GET 		= {1,         "GET"};
	HEAD 		= {2,        "HEAD"};
	POST 		= {3,        "POST"};
	PUT 		= {4,         "PUT"};
	-- pathological
	CONNECT 	= {5,     "CONNECT"};
	OPTIONS 	= {6,     "OPTIONS"};
	TRACE 		= {7,       "TRACE"};
	-- webdav
	COPY 		= {8,        "COPY"};
	LOCK 		= {9,        "LOCK"};
	MKCOL 		= {10,      "MKCOL"};
	MOVE 		= {11,       "MOVE"};
	PROPFIND 	= {12,   "PROPFIND"};
	PROPPATCH 	= {13,  "PROPPATCH"};
	SEARCH 		= {14,     "SEARCH"};
	UNLOCK 		= {15,     "UNLOCK"};
	-- subversion
	REPORT 		= {16,     "REPORT"};
	MKACTIVITY 	= {17, "MKACTIVITY"};
	CHECKOUT 	= {18,   "CHECKOUT"};
	MERGE 		= {19,      "MERGE"};
	-- upnp
	MSEARCH 	= {20,   "M-SEARCH"};
	NOTIFY 		= {21,     "NOTIFY"};
	SUBSCRIBE 	= {22,  "SUBSCRIBE"};
	UNSUBSCRIBE = {23,"UNSUBSCRIBE"};
	-- RFC-5789
	PATCH 		= {24,      "PATCH"};
	PURGE 		= {25,      "PURGE"};
}



function define_http_method_enum()
	local res = {}
	table.insert(res, "enum http_method {")

	for name,value in pairs(HTTP_METHODS) do
		table.insert(res, string.format("HTTP_%s = %d,", name, value[1]));
	end

	table.insert(res, "};")

	local enumdef = table.concat(res)

	ffi.cdef(enumdef)
end

ffi.cdef[[
enum http_parser_type {
	HTTP_REQUEST,
	HTTP_RESPONSE,
	HTTP_BOTH
};


/* Flag values for http_parser.flags field */
enum flags {
	F_CHUNKED               = 1 << 0
  , F_CONNECTION_KEEP_ALIVE = 1 << 1
  , F_CONNECTION_CLOSE      = 1 << 2
  , F_TRAILING              = 1 << 3
  , F_UPGRADE               = 1 << 4
  , F_SKIPBODY              = 1 << 5
};
]]


ffi.cdef[[
struct http_parser {
  /** PRIVATE **/
  unsigned char type : 2;     /* enum http_parser_type */
  unsigned char flags : 6;    /* F_* values from 'flags' enum; semi-public */
  unsigned char state;        /* enum state from http_parser.c */
  unsigned char header_state; /* enum header_state from http_parser.c */
  unsigned char index;        /* index into current matcher */

  uint32_t nread;          /* # bytes read in various scenarios */
  uint64_t content_length; /* # bytes in body (0 if no Content-Length header) */

  /** READ-ONLY **/
  unsigned short http_major;
  unsigned short http_minor;
  unsigned short status_code; /* responses only */
  unsigned char method;       /* requests only */
  unsigned char http_errno : 7;

  /* 1 = Upgrade header was present and the parser has exited because of that.
   * 0 = No upgrade header present.
   * Should be checked when http_parser_execute() returns in addition to
   * error checking.
   */
  unsigned char upgrade : 1;

//#if HTTP_PARSER_DEBUG
//  uint32_t error_lineno;
//#endif

  /** PUBLIC **/
  void *data; /* A pointer to get hook to the "connection" or "socket" object */
};


struct http_parser_settings {
  http_cb      on_message_begin;
  http_data_cb on_url;
  http_data_cb on_header_field;
  http_data_cb on_header_value;
  http_cb      on_headers_complete;
  http_data_cb on_body;
  http_cb      on_message_complete;
};



enum {
	UF_MAX              = 6
};

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


void http_parser_init(http_parser *parser, enum http_parser_type type);


size_t http_parser_execute(http_parser *parser,
                           const http_parser_settings *settings,
                           const char *data,
                           size_t len);


/* If http_should_keep_alive() in the on_headers_complete or
 * on_message_complete callback returns true, then this will be should be
 * the last message on the connection.
 * If you are the server, respond with the "Connection: close" header.
 * If you are the client, close the connection.
 */
int http_should_keep_alive(http_parser *parser);

/* Returns a string version of the HTTP method. */
const char *http_method_str(enum http_method m);

/* Return a string name of the given error */
const char *http_errno_name(enum http_errno err);

/* Return a string description of the given error */
const char *http_errno_description(enum http_errno err);

/* Parse a URL; return nonzero on failure */
int http_parser_parse_url(const char *buf, size_t buflen,
                          int is_connect,
                          struct http_parser_url *u);

/* Pause or un-pause the parser; a nonzero value pauses */
void http_parser_pause(http_parser *parser, int paused);
]]

-- enum http_parser_url_fields
UF_SCHEMA           = 0
UF_HOST             = 1
UF_PORT             = 2
UF_PATH             = 3
UF_QUERY            = 4
UF_FRAGMENT         = 5
UF_MAX              = 6

urlfieldnames = {
	"schema",
	"host",
	"port",
	"path",
	"query",
	"fragment",
}
function isbitset(value, bit)
	return band(value, 2^bit) > 0
end

function geturlfield(buf, parsestruct, fieldnum)
	if fieldnum < 0 or fieldnum > UF_FRAGMENT then return nil end

	local havefield = isbitset(parsestruct.field_set, fieldnum)
	local fieldname = urlfieldnames[fieldnum+1]

	if not havefield then
		return urlfieldnames[fieldnum+1], nil
	end

	local offset = parsestruct.field_data[fieldnum].off
	local len = parsestruct.field_data[fieldnum].len
	local fieldvalue = ffi.string(buf+offset, len)

	return fieldname, fieldvalue
end

local function lstringdup(lstring)
	local len = string.len(lstring)
	local buf = ffi.new("char[?]", len+1)

	ffi.copy(buf, ffi.cast("char *", lstring), len)
	buf[len] = 0;

	return buf, len;
end

--[[
	This is a nice convenience function.  You can pass in a Lua
	string containing a URL.  The return value will be a table with
	the various fields, defined by: urlfieldnames set to the
	appropriate values.
--]]


function parseurl(url)

	local buf,buflen = lstringdup(url)

	local u = ffi.new("struct http_parser_url")

	local res = http_parser.http_parser_parse_url(buf, buflen, 0, u);

	if res ~= 0 then return nil end

	local urltable = {}

	for i = 0,UF_FRAGMENT do
		local fieldname, value = geturlfield(buf, u, i)
		urltable[fieldname] = value;
	end

	return urltable;
end


local http_parser = ffi.load("http_parser")

return http_parser
