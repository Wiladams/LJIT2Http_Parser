LJIT2Http_Parser
================

This project provides an interop layer to the http-parser project from LuaJIT

The http-parser project is a core piece of the node.js project.  
It is highly performant, and written in C.

This project provides interop to the parser from the LuaJIT environment.
This will not work with plain vanilla Lua 5.x, it MUST be LuaJIT.

As the interface is fairly low level, it utilizes buffers, rather than Lua
strings.  

At the moment, there is a single helper function that makes using the 
interface a little easier, when you're doing URL parsing.

 	local values = parseurl(url)

The return value of parseurl is a table, where the keys are the names 
of the various fields of the url (schema, host, port, path, query, fragment).
If a field was absent from the url, it will be nil in the table.

This project contains a slightly modified form of the http-parser code 
in that the header adds Dllexport to the beginning of the various
functions so they will be available in the .dll.

Although this was build specifically on Windows, the FFI is not Windows specific.
It should work with any compiled version of the http_parser code.
