perl-fadecandy-fcgi
===================

Perl FCGI Server to Drive Fadecandy LED Controller

Requirements:

 * FCGI Enabled HTTP server
 * FCGI.pm
 * OPC.pm (handles communicating with fadecandy server)
 * Time::Hires (Perl builtin?)
 * XML::Simple
 * Data::Dumper (Will go away)
 * Currently requires Perl Threads enabled

When run, it listens on a port for FCGI connects from the http
server.

Example lighttpd config:

fastcgi.server = (
  "/fcgi" => (
    ( "host" => "127.0.0.1", "port" => 8888, "check-local" => "disable" )
  )
)


