# vim:set ft= ts=4 sw=4 et fdm=marker:
use lib 'lib';
use Test::Nginx::Socket;

#worker_connections(1014);
#master_process_enabled(1);
#log_level('warn');
#no_nginx_manager();

#repeat_each(1);
repeat_each(2);

plan tests => repeat_each() * (blocks() * 2 + 5);

#no_diff();
no_long_string();
run_tests();

__DATA__

=== TEST 1: basic print
--- config
    location /lua {
        # NOTE: the newline escape sequence must be double-escaped, as nginx config
        # parser will unescape first!
        access_by_lua 'ngx.print("Hello, Lua!\\n")';
        echo end;
    }
--- request
GET /lua
--- response_body
Hello, Lua!
end



=== TEST 2: basic say
--- config
    location /say {
        # NOTE: the newline escape sequence must be double-escaped, as nginx config
        # parser will unescape first!
        access_by_lua '
            ngx.say("Hello, Lua!")
            ngx.say("Yay! ", 123)';

        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /say
--- response_body
Hello, Lua!
Yay! 123



=== TEST 3: no ngx.echo
--- config
    location /lua {
        access_by_lua 'ngx.echo("Hello, Lua!\\n")';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 4: variable
--- config
    location /lua {
        # NOTE: the newline escape sequence must be double-escaped, as nginx config
        # parser will unescape first!
        access_by_lua 'v = ngx.var["request_uri"] ngx.print("request_uri: ", v, "\\n")';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua?a=1&b=2
--- response_body
request_uri: /lua?a=1&b=2



=== TEST 5: variable (file)
--- config
    location /lua {
        access_by_lua_file html/test.lua;
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- user_files
>>> test.lua
v = ngx.var["request_uri"]
ngx.print("request_uri: ", v, "\n")
--- request
GET /lua?a=1&b=2
--- response_body
request_uri: /lua?a=1&b=2



=== TEST 6: calc expression
--- config
    location /lua {
        access_by_lua_file html/calc.lua;
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- user_files
>>> calc.lua
local function uri_unescape(uri)
    local function convert(hex)
        return string.char(tonumber("0x"..hex))
    end
    local s = string.gsub(uri, "%%([0-9a-fA-F][0-9a-fA-F])", convert)
    return s
end

local function eval_exp(str)
    return loadstring("return "..str)()
end

local exp_str = ngx.var["arg_exp"]
-- print("exp: '", exp_str, "'\n")
local status, res
status, res = pcall(uri_unescape, exp_str)
if not status then
    ngx.print("error: ", res, "\n")
    return
end
status, res = pcall(eval_exp, res)
if status then
    ngx.print("result: ", res, "\n")
else
    ngx.print("error: ", res, "\n")
end
--- request
GET /lua?exp=1%2B2*math.sin(3)%2Fmath.exp(4)-math.sqrt(2)
--- response_body
result: -0.4090441561579



=== TEST 7: read $arg_xxx
--- config
    location = /lua {
        access_by_lua 'who = ngx.var.arg_who
            ngx.print("Hello, ", who, "!")';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua?who=agentzh
--- response_body chomp
Hello, agentzh!



=== TEST 8: capture location
--- config
    location /other {
        echo "hello, world";
    }

    location /lua {
        access_by_lua '
res = ngx.location.capture("/other")
ngx.print("status=", res.status, " ")
ngx.print("body=", res.body)
';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
status=200 body=hello, world



=== TEST 9: capture non-existed location
--- config
    location /lua {
        access_by_lua 'res = ngx.location.capture("/other"); ngx.print("status=", res.status)';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body: status=404



=== TEST 10: invalid capture location (not as expected...)
--- config
    location /lua {
        access_by_lua 'res = ngx.location.capture("*(#*"); ngx.say("res=", res.status)';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
res=404



=== TEST 11: nil is "nil"
--- config
    location /lua {
        access_by_lua 'ngx.print(nil)';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 12: bad argument type to ngx.location.capture
--- config
    location /lua {
        access_by_lua 'ngx.location.capture(nil)';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body_like: 500 Internal Server Error
--- error_code: 500



=== TEST 13: capture location (default 0);
--- config
 location /recur {
       access_by_lua '
           local num = tonumber(ngx.var.arg_num) or 0;
           ngx.print("num is: ", num, "\\n");

           if (num > 0) then
               res = ngx.location.capture("/recur?num="..tostring(num - 1));
               ngx.print("status=", res.status, " ");
               ngx.print("body=", res.body, "\\n");
           else
               ngx.print("end\\n");
           end
           ';

           content_by_lua 'ngx.exit(ngx.OK)';
   }
--- request
GET /recur
--- response_body
num is: 0
end



=== TEST 14: capture location
access phase not running in subrequests
--- config
 location /recur {
       access_by_lua '
           local num = tonumber(ngx.var.arg_num) or 0;
           ngx.print("num is: ", num, "\\n");

           if (num > 0) then
               res = ngx.location.capture("/recur?num="..tostring(num - 1));
               ngx.print("status=", res.status, " ");
               ngx.print("body=", res.body);
           else
               ngx.print("end\\n");
           end
           ';

           content_by_lua 'ngx.exit(ngx.OK)';
   }
--- request
GET /recur?num=3
--- response_body chomp
num is: 3
status=200 body=



=== TEST 15: setting nginx variables from within Lua
--- config
 location /set {
       set $a "";
       access_by_lua 'ngx.var.a = 32; ngx.say(ngx.var.a)';
       content_by_lua 'ngx.exit(ngx.OK)';
       add_header Foo $a;
   }
--- request
GET /set
--- response_headers
Foo: 32
--- response_body
32



=== TEST 16: nginx quote sql string 1
--- config
 location /set {
       set $a 'hello\n\r\'"\\'; # this runs after access_by_lua
       access_by_lua 'ngx.say(ngx.quote_sql_str(ngx.var.a))';
       content_by_lua 'ngx.exit(ngx.OK)';
   }
--- request
GET /set
--- response_body
'hello\n\r\'\"\\'



=== TEST 17: nginx quote sql string 2
--- config
location /set {
    #set $a "hello\n\r'\"\\";
    access_by_lua 'ngx.say(ngx.quote_sql_str("hello\\n\\r\'\\"\\\\"))';
    content_by_lua 'ngx.exit(ngx.OK)';
}
--- request
GET /set
--- response_body
'hello\n\r\'\"\\'



=== TEST 18: use dollar
--- config
location /set {
    access_by_lua '
        local s = "hello 112";
        ngx.say(string.find(s, "%d+$"))';

    content_by_lua 'ngx.exit(ngx.OK)';
}
--- request
GET /set
--- response_body
79



=== TEST 19: subrequests do not share variables of main requests by default
--- config
location /sub {
    echo $a;
}
location /parent {
    set $a 12;
    access_by_lua 'res = ngx.location.capture("/sub"); ngx.print(res.body)';
    content_by_lua 'ngx.exit(ngx.OK)';
}
--- request
GET /parent
--- response_body eval: "\n"



=== TEST 20: subrequests can share variables of main requests
--- config
location /sub {
    echo $a;
}
location /parent {
    set $a '';
    access_by_lua '
        ngx.var.a = 12;
        res = ngx.location.capture(
            "/sub",
            { share_all_vars = true }
        );
        ngx.print(res.body)
    ';
    content_by_lua 'ngx.exit(ngx.OK)';
}
--- request
GET /parent
--- response_body
12



=== TEST 21: main requests use subrequests' variables
--- config
location /sub {
    set $a 12;
}
location /parent {
    access_by_lua '
        res = ngx.location.capture("/sub", { share_all_vars = true });
        ngx.say(ngx.var.a)
    ';

    content_by_lua 'ngx.exit(ngx.OK)';
}
--- request
GET /parent
--- response_body
12



=== TEST 22: main requests do NOT use subrequests' variables
--- config
location /sub {
    set $a 12;
}
location /parent {
    access_by_lua '
        res = ngx.location.capture("/sub", { share_all_vars = false });
        ngx.say(ngx.var.a)
    ';
}
--- request
GET /parent
--- response_body_like eval: "\n"



=== TEST 23: capture location headers
--- config
    location /other {
        default_type 'foo/bar';
        echo "hello, world";
    }

    location /lua {
        access_by_lua '
            res = ngx.location.capture("/other");
            ngx.say("type: ", res.header["Content-Type"]);
        ';

        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
type: foo/bar



=== TEST 24: capture location headers
--- config
    location /other {
        default_type 'foo/bar';
        rewrite_by_lua '
            ngx.header.Bar = "Bah";
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }

    location /lua {
        access_by_lua '
            res = ngx.location.capture("/other");
            ngx.say("type: ", res.header["Content-Type"]);
            ngx.say("Bar: ", res.header["Bar"]);
        ';

        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
type: foo/bar
Bar: Bah



=== TEST 25: capture location headers
--- config
    location /other {
        default_type 'foo/bar';
        access_by_lua '
            ngx.header.Bar = "Bah";
            ngx.header.Bar = nil;
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }

    location /lua {
        access_by_lua '
            res = ngx.location.capture("/other");
            ngx.say("type: ", res.header["Content-Type"]);
            ngx.say("Bar: ", res.header["Bar"] or "nil");
        ';
        content_by_lua 'ngx.exit(ngx.OK)';
    }
--- request
GET /lua
--- response_body
type: foo/bar
Bar: nil



=== TEST 26: access_by_lua runs after ngx_access
--- config
    location /lua {
        deny all;

        access_by_lua '
            ngx.exit(ngx.HTTP_INTERNAL_SERVER_ERROR)
        ';

        content_by_lua return;
    }
--- request
GET /lua
--- response_body_like: 403 Forbidden
--- error_code: 403



=== TEST 27: auth_request runs before ngx_access
--- config
    location /lua {
        deny all;

        auth_request /auth;

        content_by_lua return;
    }
--- request
GET /lua
--- response_body_like: 403 Forbidden
--- error_code: 403
--- SKIP



=== TEST 28: access_by_lua shouldn't send headers automatically (on simple return)
--- config
    location /lua {
        access_by_lua 'return';

        proxy_pass http://127.0.0.1:$server_port/foo;
    }

    location = /foo {
        default_type 'text/css';
        add_header Bar Baz;
        echo foo;
    }
--- request
GET /lua
--- response_headers
Bar: Baz
Content-Type: text/css
--- response_body
foo



=== TEST 29: access_by_lua shouldn't send headers automatically (on simple exit)
--- config
    location /lua {
        access_by_lua 'ngx.exit(ngx.OK)';

        proxy_pass http://127.0.0.1:$server_port/foo;
    }

    location = /foo {
        default_type 'text/css';
        add_header Bar Baz;
        echo foo;
    }
--- request
GET /lua
--- response_headers
Bar: Baz
Content-Type: text/css
--- response_body
foo



=== TEST 30: short circuit
--- config
    location /lua {
        rewrite_by_lua '
            ngx.say("Hi")
            ngx.eof()
            ngx.exit(ngx.HTTP_OK)
        ';

        content_by_lua '
            print("HERE")
            ngx.print("BAD")
        ';
    }
--- request
GET /lua
--- response_body
Hi

