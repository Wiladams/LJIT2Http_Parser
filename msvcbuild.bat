@set LJCOMPILE=cl /nologo /c /MD /O2 /W3 /D_CRT_SECURE_NO_DEPRECATE
@set LJLINK=link /nologo

%LJCOMPILE% http_parser.c

%LJLINK% /DLL /out:http_parser.dll http_parser.obj

