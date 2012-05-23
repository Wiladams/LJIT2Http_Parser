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
local bor = bit.bor
local lshift = bit.lshift
local rshift = bit.rshift

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

--[[
/* Tokens as defined by rfc 2616. Also lowercases them.
 *        token       = 1*<any CHAR except CTLs or separators>
 *     separators     = "(" | ")" | "<" | ">" | "@"
 *                    | "," | ";" | ":" | "\" | <">
 *                    | "/" | "[" | "]" | "?" | "="
 *                    | "{" | "}" | SP | HT
 */
 --]]

tokens = ffi.new("char[256]", {
--   0 nul    1 soh    2 stx    3 etx    4 eot    5 enq    6 ack    7 bel
        0,       0,       0,       0,       0,       0,       0,       0,
--   8 bs     9 ht    10 nl    11 vt    12 np    13 cr    14 so    15 si
        0,       0,       0,       0,       0,       0,       0,       0,
--  16 dle   17 dc1   18 dc2   19 dc3   20 dc4   21 nak   22 syn   23 etb
        0,       0,       0,       0,       0,       0,       0,       0,
--  24 can   25 em    26 sub   27 esc   28 fs    29 gs    30 rs    31 us
        0,       0,       0,       0,       0,       0,       0,       0,
--  32 sp    33  !    34  "    35  #    36  $    37  %    38  &    39  '
        0,      33,      0,       35,      36,      37,      38,      39,
--  40  (    41  )    42  *    43  +    44  ,    45  -    46  .    47  /
        0,       0,      42,      43,       0,      45,      46,       0,
--  48  0    49  1    50  2    51  3    52  4    53  5    54  6    55  7
       48,      49,      50,      51,      52,      53,      54,      55,
--  56  8    57  9    58  :    59  ;    60  <    61  =    62  >    63  ?
       56,      57,       0,       0,       0,       0,       0,       0,
--  64  @    65  A    66  B    67  C    68  D    69  E    70  F    71  G
        0,      97,      98,      99,     100,     101,     102,     103,
--  72  H    73  I    74  J    75  K    76  L    77  M    78  N    79  O
	  104,     105,     106,     107,     108,     109,     110,     111,
--  80  P    81  Q    82  R    83  S    84  T    85  U    86  V    87  W
	  112,     113,     114,     115,     116,     117,     118,     119,
--  88  X    89  Y    90  Z    91  [    92  \    93  ]    94  ^    95  _
	  120,     121,     122,      0,       0,       0,       94,      95,
--  96  `    97  a    98  b    99  c   100  d   101  e   102  f   103  g
       96,      97,      98,      99,     100,     101,     102,     103,
-- 104  h   105  i   106  j   107  k   108  l   109  m   110  n   111  o
	  104,     105,     106,     107,     108,     109,     110,     111,
-- 112  p   113  q   114  r   115  s   116  t   117  u   118  v   119  w
	  112,     113,     114,     115,     116,     117,     118,     119,
-- 120  x   121  y   122  z   123  {   124  |   125  }   126  ~   127 del
	  120,     121,     122,      0,      124,      0,      126,       0
});


local T
if HTTP_PARSER_STRICT then
	T = 0
else
	T = 1
end


local normal_url_char = ffi.new("uint8_t[256]", {
--   0 nul    1 soh    2 stx    3 etx    4 eot    5 enq    6 ack    7 bel
        0,       0,       0,       0,       0,       0,       0,       0,
--   8 bs     9 ht    10 nl    11 vt    12 np    13 cr    14 so    15 si
        0,       T,       0,       0,       T,       0,       0,       0,
--  16 dle   17 dc1   18 dc2   19 dc3   20 dc4   21 nak   22 syn   23 etb
        0,       0,       0,       0,       0,       0,       0,       0,
--  24 can   25 em    26 sub   27 esc   28 fs    29 gs    30 rs    31 us
        0,       0,       0,       0,       0,       0,       0,       0,
--  32 sp    33  !    34  "    35  #    36  $    37  %    38  &    39  '
        0,       1,       1,       0,       1,       1,       1,       1,
--  40  (    41  )    42  *    43  +    44  ,    45  -    46  .    47  /
        1,       1,       1,       1,       1,       1,       1,       1,
--  48  0    49  1    50  2    51  3    52  4    53  5    54  6    55  7
        1,       1,       1,       1,       1,       1,       1,       1,
--  56  8    57  9    58  :    59  ;    60  <    61  =    62  >    63  ?
        1,       1,       1,       1,       1,       1,       1,       0,
--  64  @    65  A    66  B    67  C    68  D    69  E    70  F    71  G
        1,       1,       1,       1,       1,       1,       1,       1,
--  72  H    73  I    74  J    75  K    76  L    77  M    78  N    79  O
        1,       1,       1,       1,       1,       1,       1,       1,
--  80  P    81  Q    82  R    83  S    84  T    85  U    86  V    87  W
        1,       1,       1,       1,       1,       1,       1,       1,
--  88  X    89  Y    90  Z    91  [    92  \    93  ]    94  ^    95  _
        1,       1,       1,       1,       1,       1,       1,       1,
--  96  `    97  a    98  b    99  c   100  d   101  e   102  f   103  g
        1,       1,       1,       1,       1,       1,       1,       1,
-- 104  h   105  i   106  j   107  k   108  l   109  m   110  n   111  o
        1,       1,       1,       1,       1,       1,       1,       1,
-- 112  p   113  q   114  r   115  s   116  t   117  u   118  v   119  w
        1,       1,       1,       1,       1,       1,       1,       1,
-- 120  x   121  y   122  z   123  {   124  |   125  }   126  ~   127 del
        1,       1,       1,       1,       1,       1,       1,       0});

T = nil;

T_NUL = 0;
T_SOH = 1;
T_STX = 2;
T_ETX = 3;
T_EOT = 4;
T_ENQ = 5;
T_ACK = 6;
T_BEL = 7;
T_BS = 8;
T_HT = 9;
T_LF = 10;
T_VT = 11;
T_FF = 12;
T_CR = 13;
T_SO = 14;
T_SI = 15;
T_DLE = 16;
T_DC1 = 17;
T_DC2 = 18;
T_DC3 = 19;
T_DC4 = 20;
T_NAK = 21;
T_SYN = 22;
T_ETB = 23;
T_CAN = 24;
T_EM = 25;
T_SUB = 26;
T_ESC = 27;
T_FS = 28;
T_GS = 29;
T_RS = 30;
T_US = 31;
T_SP = 32;
T_EXCLAIM = 33;
T_DQUOTE = 34;
T_HASH = 35;
T_DOLLAR = 36;
T_PERCENT = 37;
T_AMP = 38;
T_SQUOTE = 39;
T_LPAREN = 40;
T_RPAREN = 41;
T_ASTERISK = 42;
T_PLUS = 43;
T_COMMA = 44;
T_HYPHEN = 45;
T_PERIOD = 46;
T_SLASH = 47;
T_0 = 48;
T_1 = 49;
T_2 = 50;
T_3 = 51;
T_4 = 52;
T_5 = 53;
T_6 = 54;
T_7 = 55;
T_8 = 56;
T_9 = 57;
T_COLON = 58;
T_SEMI = 59;
T_LANGLE = 60;
T_EQUAL = 61;
T_RANGLE = 62;
T_QUES = 63;
T_AT = 64;
T_A = 65;
T_B = 66;
T_C = 67;
T_D = 68;
T_E = 69;
T_F = 70;
T_G = 71;
T_H = 72;
T_I = 73;
T_J = 74;
T_K = 75;
T_L = 76;
T_M = 77;
T_N = 78;
T_O = 79;
T_P = 80;
T_Q = 81;
T_R = 82;
T_S = 83;
T_T = 84;
T_U = 85;
T_V = 86;
T_W = 87;
T_X = 88;
T_Y = 89;
T_Z = 90;
T_LBRACKET = 91;
T_BACKSLASH = 92;
T_RBRACKET = 93;
T_HAT = 94;
T_UNDER = 95;
T_LQUOTE = 96;
T_a = 97;
T_b = 98;
T_c = 99;
T_d = 100;
T_e = 101;
T_f = 102;
T_g = 103;
T_h = 104;
T_i = 105;
T_j = 106;
T_k = 107;
T_l = 108;
T_m = 109;
T_n = 110;
T_o = 111;
T_p = 112;
T_q = 113;
T_r = 114;
T_s = 115;
T_t = 116;
T_u = 117;
T_v = 118;
T_w = 119;
T_x = 120;
T_y = 121;
T_z = 122;
T_LCURLY = 123;
T_PIPE = 124;
T_RCURLY = 125;
T_TILDE = 126;
T_DEL = 127;


CR = string.byte('\r')
LF = string.byte('\n')
function LOWER(c)            return band(0xff,bor(c, 0x20)) end
function IS_ALPHA(c)         return (LOWER(c) >= string.byte('a') and LOWER(c) <= string.byte('z')) end
function IS_NUM(c)           return (c >= string.byte('0') and c <= string.byte('9')) end
function IS_ALPHANUM(c)      return (IS_ALPHA(c) or IS_NUM(c)) end
function IS_HEX(c)           return (IS_NUM(c) or (LOWER(c) >= string.byte('a') and LOWER(c) <= string.byte('f'))) end

--[[
#if HTTP_PARSER_STRICT
#define TOKEN(c)            (tokens[(unsigned char)c])
#define IS_URL_CHAR(c)      (normal_url_char[(unsigned char) (c)])
#define IS_HOST_CHAR(c)     (IS_ALPHANUM(c) || (c) == '.' || (c) == '-')
#else
--]]
function TOKEN(c)
	local T_space = string.byte(' ');

	if (c == T_space) then
		return T_space
	end

	return tokens[c]
end

function IS_URL_CHAR(c)
	return (normal_url_char[c]>0 or band((c), 0x80) >0)
end

function IS_HOST_CHAR(c)
	return (IS_ALPHANUM(c) or (c) == string.byte('.') or (c) == string.byte('-') or (c) == string.byte('_'))
end


-- enum flags {
F_CHUNKED               = 0x01;	-- lshift(1 << 0);
F_CONNECTION_KEEP_ALIVE = 0x02;	-- lshift(1 << 1);
F_CONNECTION_CLOSE      = 0x04;	-- lshift(1 << 2);
F_TRAILING              = 0x08;	-- lshift(1 << 3);
F_UPGRADE               = 0x10; -- lshift(1 << 4);
F_SKIPBODY              = 0x20; -- lshift(1 << 5);


-- enum http_parser_type {
HTTP_REQUEST = 0
HTTP_RESPONSE = 1
HTTP_BOTH = 2



HTTP_METHODS = {
{0,     "DELETE"};
{1,        "GET"};
{2,       "HEAD"};
{3,       "POST"};
{4,        "PUT"};
-- pathological
{5,    "CONNECT"};
{6,    "OPTIONS"};
{7,      "TRACE"};
-- webdav
{8,       "COPY"};
{9,       "LOCK"};
{10,     "MKCOL"};
{11,      "MOVE"};
{12,  "PROPFIND"};
{13, "PROPPATCH"};
{14,    "SEARCH"};
{15,    "UNLOCK"};
-- subversion
{16,    "REPORT"};
{17,"MKACTIVITY"};
{18,  "CHECKOUT"};
{19,     "MERGE"};
-- upnp
{20,  "MSEARCH"};	-- M-SEARCH
{21,    "NOTIFY"};
{22, "SUBSCRIBE"};
{23, "UNSUBSCRIBE"};
-- RFC-5789
{24,     "PATCH"};
{25,     "PURGE"};
};


local function define_http_method_constants()
	local res = {}

	for i,value in ipairs(HTTP_METHODS) do
		table.insert(res, string.format("HTTP_%s = %d;\n", value[2], value[1]));
	end


	local str = table.concat(res)
	local f = loadstring(str);
	f();
end

define_http_method_constants()

function http_method_str(m)
	return HTTP_METHODS[m+1][2];
end


--[[
	Definitions For Error Numbers/Names
/* Map for errno-related constants
 *
 * The provided argument should be a macro that takes 2 arguments.
 */

--]]
HTTP_ERRORS = {
  -- No error
{0, "OK", "success"};

  -- Callback-related errors
{1, "CB_message_begin", "the on_message_begin callback failed"};
{2, "CB_url", "the on_url callback failed"};
{3, "CB_header_field", "the on_header_field callback failed"};
{4, "CB_header_value", "the on_header_value callback failed"};
{5, "CB_headers_complete", "the on_headers_complete callback failed"};
{6, "CB_body", "the on_body callback failed"};
{7, "CB_message_complete", "the on_message_complete callback failed"};

  -- Parsing-related errors
{8, "INVALID_EOF_STATE", "stream ended at an unexpected time"};
{9, "HEADER_OVERFLOW", "too many header bytes seen; overflow detected"};
{10, "CLOSED_CONNECTION", "data received after completed connection: close message"};
{11, "INVALID_VERSION", "invalid HTTP version"};
{12, "INVALID_STATUS", "invalid HTTP status code"};
{13, "INVALID_METHOD", "invalid HTTP method"};
{14, "INVALID_URL", "invalid URL"};
{15, "INVALID_HOST", "invalid host"};
{16, "INVALID_PORT", "invalid port"};
{17, "INVALID_PATH", "invalid path"};
{18, "INVALID_QUERY_STRING", "invalid query string"};
{19, "INVALID_FRAGMENT", "invalid fragment"};
{20, "LF_EXPECTED", "LF character expected"};
{21, "INVALID_HEADER_TOKEN", "invalid character in header"};
{22, "INVALID_CONTENT_LENGTH", "invalid character in content-length header"};
{23, "INVALID_CHUNK_SIZE", "invalid character in chunk size header"};
{24, "INVALID_CONSTANT", "invalid constant string"};
{25, "INVALID_INTERNAL_STATE", "encountered unexpected internal state"};
{26, "STRICT", "strict mode assertion failed"};
{27, "PAUSED", "parser is paused"};
{28, "UNKNOWN", "an unknown error occurred"};
};


local function define_http_error_constants()
	local res = {}

	for i,value in ipairs(HTTP_ERRORS) do
		table.insert(res, string.format("HPE_%s = %d;\n", value[2], value[1]));
	end


	local str = table.concat(res)
--print(str)
	local f = loadstring(str);
	f();
end

define_http_error_constants()

function http_errno_name(err)
	return HTTP_ERRORS[err+1][2];
end

function http_errno_description(err)
	return HTTP_ERRORS[err+1][3];
end


-- parser state constants
s_dead = 1; -- important that this is > 0

 s_start_req_or_res = 2;
 s_res_or_resp_H = 3;
 s_start_res = 4;
 s_res_H = 5;
 s_res_HT = 6;
 s_res_HTT = 7;
 s_res_HTTP = 8;
 s_res_first_http_major = 9;
 s_res_http_major = 10;
 s_res_first_http_minor = 11;
 s_res_http_minor = 12;
 s_res_first_status_code = 13;
 s_res_status_code = 14;
 s_res_status = 15;
 s_res_line_almost_done = 16;

 s_start_req = 17;

 s_req_method = 18;
 s_req_spaces_before_url = 19;
 s_req_schema = 20;
 s_req_schema_slash = 21;
 s_req_schema_slash_slash = 22;
 s_req_host_start = 23;
 s_req_host_v6_start = 24;
 s_req_host_v6 = 25;
 s_req_host_v6_end = 26;
 s_req_host = 27;
 s_req_port_start = 28;
 s_req_port = 29;
 s_req_path = 30;
 s_req_query_string_start = 31;
 s_req_query_string = 32;
 s_req_fragment_start = 33;
 s_req_fragment = 34;
 s_req_http_start = 35;
 s_req_http_H = 36;
 s_req_http_HT = 37;
 s_req_http_HTT = 38;
 s_req_http_HTTP = 39;
 s_req_first_http_major = 40;
 s_req_http_major = 41;
 s_req_first_http_minor = 42;
 s_req_http_minor = 43;
 s_req_line_almost_done = 44;

 s_header_field_start = 45;
 s_header_field = 46;
 s_header_value_start = 47;
 s_header_value = 48;
 s_header_value_lws = 49;

 s_header_almost_done = 50;

 s_chunk_size_start = 51;
 s_chunk_size = 52;
 s_chunk_parameters = 53;
 s_chunk_size_almost_done = 54;

 s_headers_almost_done = 55;
 s_headers_done = 56;

  --[[
   Important: 's_headers_done' must be the last 'header' state. All
   states beyond this must be 'body' states. It is used for overflow
   checking. See the PARSING_HEADER() macro.
--]]

 s_chunk_data = 57;
 s_chunk_data_almost_done = 58;
 s_chunk_data_done = 59;

 s_body_identity = 60;
 s_body_identity_eof = 61;

 s_message_done = 62;



function PARSING_HEADER(state)
	return (state <= s_headers_done)
end




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



local lib = ffi.load("http_parser")


--[[
/* Our URL parser.
 *
 * This is designed to be shared by http_parser_execute() for URL validation,
 * hence it has a state transition + byte-for-byte interface. In addition, it
 * is meant to be embedded in http_parser_parse_url(), which does the dirty
 * work of turning state transitions URL components for its API.
 *
 * This function should only be invoked with non-space characters. It is
 * assumed that the caller cares about (and can detect) the transition between
 * URL and non-URL states by looking for these.
 */
 --]]


function parse_url_char(s, ch)

	if (ch == string.byte(' ') or ch == string.byte('\r') or ch == string.byte('\n')) then
		return s_dead;
	end

	if HTTP_PARSER_STRICT then
		if (ch == string.byte('\t') or ch == string.byte('\f')) then
			return s_dead;
		end
	end

    if s == s_req_spaces_before_url then
		-- Proxied requests are followed by scheme of an absolute URI (alpha).
		-- All methods except CONNECT are followed by '/' or '*'.
		--

		if (ch == string.byte('/') or ch == string.byte('*')) then
			return s_req_path;
		end

		if (IS_ALPHA(ch)) then
			return s_req_schema;
		end

    elseif s == s_req_schema then
		if (IS_ALPHA(ch)) then
			return s;
		end

		if (ch == string.byte(':')) then
			return s_req_schema_slash;
		end
    elseif s == s_req_schema_slash then
		if (ch == string.byte('/')) then
			return s_req_schema_slash_slash;
		end

    elseif s == s_req_schema_slash_slash then
		if (ch == string.byte('/')) then
			return s_req_host_start;
		end

    elseif s == s_req_host_start then
		if (ch == string.byte('[')) then
			return s_req_host_v6_start;
		end

		if (IS_HOST_CHAR(ch)) then
			return s_req_host;
		end

    elseif s == s_req_host or
			s == s_req_host_v6_end  then

		if s == s_req_host then
			if (IS_HOST_CHAR(ch)) then
				return s_req_host;
			end
		end

		-- FALLTHROUGH
		if ch == string.byte(':') then
			return s_req_port_start;
		end

		if ch == string.byte('/') then
			return s_req_path;
		end

		if ch == string.byte('?') then
			return s_req_query_string_start;
		end
	elseif s == s_req_host_v6 or s == s_req_host_v6_start then
		if s == s_req_host_v6 then
			if (ch == string.byte(']')) then
				return s_req_host_v6_end;
			end
		end

		-- FALLTHROUGH
		if (IS_HEX(ch) or ch == string.byte(':')) then
			return s_req_host_v6;
		end

    elseif s == s_req_port or s == s_req_port_start then
        if s == s_req_port then
			if ch == string.byte('/') then
				return s_req_path;
			elseif ch == string.byte('?') then
				return s_req_query_string_start;
			end
		end

		-- FALLTHROUGH
		if (IS_NUM(ch)) then
			return s_req_port;
		end

    elseif s == s_req_path then
		if (IS_URL_CHAR(ch)) then
			return s;
		end

        if ch == string.byte('?') then
			return s_req_query_string_start;
		elseif ch == string.byte('#') then
			return s_req_fragment_start;
		end
    elseif s == s_req_query_string_start or
		s == s_req_query_string then

		if (IS_URL_CHAR(ch)) then
			return s_req_query_string;
		end

        if ch == string.byte('?') then
          -- allow extra '?' in query string
			return s_req_query_string;
		elseif ch == string.byte('#') then
			return s_req_fragment_start;
		end

    elseif s == s_req_fragment_start then
		if (IS_URL_CHAR(ch)) then
			return s_req_fragment;
		end

		if ch == string.byte('?') then
			return s_req_fragment;
        elseif ch == string.byte('#') then
			return s;
		end

    elseif s == s_req_fragment then
		if (IS_URL_CHAR(ch)) then
			return s;
		end


        if ch ==  string.byte('?') or
           ch ==  string.byte('#') then
			return s;
		end

    end

	-- We should never fall out of the switch above unless there's an error
	return s_dead;
end



--struct http_parser_url *u
function http_parser_parse_url(buf, buflen, is_connect, u)

	local s;
	local p = buf;

	u.port = 0;
	u.field_set = 0;

	if is_connect then
		s = s_req_host_start
	else
		s = s_req_spaces_before_url
	end

	local uf = UF_MAX;
	local old_uf = UF_MAX;



	while (p < buf + buflen) do
		s = parse_url_char(s, p[0]);

		-- Figure out the next field that we're operating on
		if s == s_dead then
			print("s == s_dead");
			return 1;
		end

		-- Skip delimeters
		if s == s_req_schema_slash or
			s == s_req_schema_slash_slash or
			s == s_req_host_start or
			s == s_req_host_v6_start or
			s == s_req_host_v6_end or
			s == s_req_port_start or
			s == s_req_query_string_start or
			s == s_req_fragment_start then
		else
			if s == s_req_schema then
				uf = UF_SCHEMA;
			elseif s == s_req_host or
				s == s_req_host_v6 then
				uf = UF_HOST;
			elseif s == s_req_port then
				uf = UF_PORT;
			elseif s == s_req_path then
				uf = UF_PATH;
			elseif s == s_req_query_string then
				uf = UF_QUERY;
			elseif s == s_req_fragment then
				uf = UF_FRAGMENT;
			else
				assert(false, "Unexpected state");
				return 1;
			end

			-- Nothing's changed; soldier on
			if (uf == old_uf) then
				u.field_data[uf].len = u.field_data[uf].len + 1;
				--continue;
			else
				u.field_data[uf].off = p - buf;
				u.field_data[uf].len = 1;

				u.field_set = bor(u.field_set, lshift(1,uf));
				old_uf = uf;
			end
		end

		p = p + 1;
	end

	-- CONNECT requests can only contain "hostname:port"
	if (is_connect and u.field_set ~= bor(lshift(1, UF_HOST), lshift(1, UF_PORT))) then
		return 1;
	end

	-- Make sure we don't end somewhere unexpected
	if s ==  s_req_host_v6_start or
		s == s_req_host_v6 or
		s ==s_req_host_v6_end or
		s ==s_req_host or
		s == s_req_port_start then
		return 1;
	end

	if band(u.field_set, lshift(1, UF_PORT)) > 0 then
		print("getting port");
		-- Don't bother with endp; we've already validated the string
		-- WAA - bit of waste here.  It would be better if a lua string
		-- did not have to be created.  Need strtoul implementation.
		local v = strtoul(buf + u.field_data[UF_PORT].off, nil, 10);
		--local v = tonumber(ffi.string(buf + u.field_data[UF_PORT].off), 10);

		-- Ports have a max value of 2^16
		if (v > 0xffff) then
			return 1;
		end

		u.port = v;
	end

	return 0;
end


http_parser_url = nil
http_parser_url_mt = {
}
http_parser_url = ffi.metatype("struct http_parser_url", http_parser_url_mt);



http_parser_settings = nil
http_parser_settings_mt = {
	__index = {
		new = function()
			local newone = ffi.cast("struct http_parser_settings *", ffi.new("uint8_t[?]", ffi.sizeof("http_parser_settings")));

			return newone;
		end;
	};
}
http_parser_settings = ffi.metatype("http_parser_settings", http_parser_settings_mt);


http_parser = nil
http_parser_mt = {
	__index = {
		new = function()
			local parser = ffi.cast("struct http_parser *", ffi.new("char *",ffi.sizeof("struct http_parser")))
			return parser;
		end;

		init = function(self, parser_type)
			-- brief sanity check
			if parser_type < 0 or parser_type > HTTP_BOTH then return end


			local data = self.data; -- preserve application data
			ffi.fill(self, 0, ffi.sizeof(self));
			self.data = data;
			self.type = parser_type;
			if (parser_type == HTTP_REQUEST) then
				self.state = s_start_req;
			else
				if (parser_type == HTTP_RESPONSE) then
					self.state = s_start_res;
				else
					self.state = s_start_req_or_res;
				end
			end

			self.http_errno = HPE_OK;
		end;

		execute = function(self, settings, data, len)
			return lib.http_parser_execute(self,settings,data,len);
		end;

		pause = function(self, paused)
			-- Users should only be pausing/unpausing a parser that is not in an error
			--state. In non-debug builds, there's not much that we can do about this
			-- other than ignore it.
			--
			if self.http_errno == HPE_OK or
			  self.http_errno == HPE_PAUSED then
				if paused then
					self.http_errno = HPE_PAUSED;
				else
					self.http_errno = HPE_OK;
				end
			else
				assert(false, "Attempting to pause parser in error state");
			end
		end;

		should_keep_alive = function(self)
			return lib.http_should_keep_alive(self);
		end
	};
}
http_parser = ffi.metatype("struct http_parser", http_parser_mt);




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

	local res = http_parser_parse_url(buf, buflen, true, u);

	if res ~= 0 then return nil end

	local urltable = {}

	for i = 0,UF_FRAGMENT do
		local fieldname, value = geturlfield(buf, u, i)
		urltable[fieldname] = value;
	end

	return urltable;
end


local lib = ffi.load("http_parser")

return lib
