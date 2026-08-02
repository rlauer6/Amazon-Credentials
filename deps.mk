# ./lib/Amazon/Credentials.pm.in
./lib/Amazon/Credentials.pm: \
    ./lib/Amazon/Credentials/HTTP/Response.pm \
    ./lib/Amazon/Credentials/HTTP/UserAgent.pm

# ./lib/Amazon/Credentials/HTTP/UserAgent.pm.in
./lib/Amazon/Credentials/HTTP/UserAgent.pm: \
    ./lib/Amazon/Credentials/HTTP/Response.pm

