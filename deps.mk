# ./lib/Amazon/Credentials.pm.in
./lib/Amazon/Credentials.pm: \
    ./lib/Amazon/Credentials/HTTP/Response.pm \
    ./lib/Amazon/Credentials/HTTP/UserAgent.pm \
    ./lib/Amazon/Credentials/Provider/SSO.pm \
    ./lib/Amazon/Credentials/Utils.pm

# ./lib/Amazon/Credentials/HTTP/UserAgent.pm.in
./lib/Amazon/Credentials/HTTP/UserAgent.pm: \
    ./lib/Amazon/Credentials/HTTP/Response.pm

# ./lib/Amazon/Credentials/Provider/AssumeRole.pm.in
./lib/Amazon/Credentials/Provider/AssumeRole.pm: \
    ./lib/Amazon/Credentials/HTTP/UserAgent.pm \
    ./lib/Amazon/Credentials/Provider.pm

# ./lib/Amazon/Credentials/Provider/Config.pm.in
./lib/Amazon/Credentials/Provider/Config.pm: \
    ./lib/Amazon/Credentials/Provider.pm \
    ./lib/Amazon/Credentials/Role/File.pm

# ./lib/Amazon/Credentials/Provider/Container.pm.in
./lib/Amazon/Credentials/Provider/Container.pm: \
    ./lib/Amazon/Credentials/HTTP/UserAgent.pm \
    ./lib/Amazon/Credentials/Provider.pm \
    ./lib/Amazon/Credentials/Utils.pm

# ./lib/Amazon/Credentials/Provider/Env.pm.in
./lib/Amazon/Credentials/Provider/Env.pm: \
    ./lib/Amazon/Credentials/Provider.pm

# ./lib/Amazon/Credentials/Provider/InstanceRole.pm.in
./lib/Amazon/Credentials/Provider/InstanceRole.pm: \
    ./lib/Amazon/Credentials/HTTP/UserAgent.pm \
    ./lib/Amazon/Credentials/Provider.pm

# ./lib/Amazon/Credentials/Provider/Process.pm.in
./lib/Amazon/Credentials/Provider/Process.pm: \
    ./lib/Amazon/Credentials/Provider.pm \
    ./lib/Amazon/Credentials/Role/File.pm

# ./lib/Amazon/Credentials/Provider/SSO.pm.in
./lib/Amazon/Credentials/Provider/SSO.pm: \
    ./lib/Amazon/Credentials/HTTP/UserAgent.pm \
    ./lib/Amazon/Credentials/Provider.pm \
    ./lib/Amazon/Credentials/Role/File.pm \
    ./lib/Amazon/Credentials/Role/SSOCache.pm

# ./lib/Amazon/Credentials/Provider/WebIdentity.pm.in
./lib/Amazon/Credentials/Provider/WebIdentity.pm: \
    ./lib/Amazon/Credentials/HTTP/UserAgent.pm \
    ./lib/Amazon/Credentials/Provider.pm

# ./lib/Amazon/Credentials/Resolver/Profile.pm.in
./lib/Amazon/Credentials/Resolver/Profile.pm: \
    ./lib/Amazon/Credentials/Provider/AssumeRole.pm \
    ./lib/Amazon/Credentials/Provider/Config.pm \
    ./lib/Amazon/Credentials/Provider/Container.pm \
    ./lib/Amazon/Credentials/Provider/Env.pm \
    ./lib/Amazon/Credentials/Provider/InstanceRole.pm \
    ./lib/Amazon/Credentials/Provider/Process.pm \
    ./lib/Amazon/Credentials/Provider/SSO.pm \
    ./lib/Amazon/Credentials/Provider/WebIdentity.pm \
    ./lib/Amazon/Credentials/Role/File.pm

# ./lib/Amazon/Credentials/Role/File.pm.in
./lib/Amazon/Credentials/Role/File.pm: \
    ./lib/Amazon/Credentials/Utils.pm

# ./lib/Amazon/Credentials/Role/SSOCache.pm.in
./lib/Amazon/Credentials/Role/SSOCache.pm: \
    ./lib/Amazon/Credentials/HTTP/UserAgent.pm

