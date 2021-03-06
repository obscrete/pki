-module(keydir_network_client).
-export([create/3, read/3, update/3, delete/4]).
-export([alive/2]).
-export([recv/3, send/2]).
-export_type([keydir_access/0]).

-include_lib("apptools/include/log.hrl").
-include("../include/keydir_serv.hrl").
-include("../include/keydir_network_client.hrl").
-include("keydir_network.hrl").

-type keydir_access() :: {tor_only,
                       {OnionHostname :: binary(), inet:port_number()}} |
                      {tcp_only,
                       {inet:ip4_address() | inet:hostname(),
                        inet:port_number()}} |
                      {tor_fallback_to_tcp,
                       {OnionHostname :: binary(), inet:port_number()},
                       {inet:ip4_address() | inet:hostname(),
                        inet:port_number()}}.
-type transport() :: {socks, pid()} | inet:socket().

%% Exported: create

-spec create(#keydir_user{}, #keydir_network_client_options{}, timeout()) ->
          ok | {error, any()}.

create(KeydirUser, Options, Timeout) ->
    ?dbg_log({create, KeydirUser, Options, Timeout}),
    case connect(Timeout, Options) of
        {ok, Transport} ->
            try
                ok = keydir_util:write_integer(1, Transport, ?CREATE),
                ok = keydir_util:write_user(Transport, KeydirUser),
                case keydir_util:read_integer(1, Transport, Timeout) of
                    ?OK ->
                        ok;
                    ?ERROR ->
                        Reason = keydir_util:read_binary(2, Transport, Timeout),
                        {error, Reason}
                end
            catch
                throw:{keydir_util, KeydirUtilReason} ->
                    close(Transport),
                    {error, KeydirUtilReason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% Exported: read

-spec read(binary(), #keydir_network_client_options{}, timeout()) ->
          {ok, #keydir_user{}} | {error, any()}.

read(Name, Options, Timeout) ->
    ?dbg_log({read, Name, Timeout, Options}),
    case connect(Timeout, Options) of
        {ok, Transport} ->
            try
                ok = keydir_util:write_integer(1, Transport, ?READ),
                ok = keydir_util:write_binary(1, Transport, Name),
                case keydir_util:read_integer(1, Transport, Timeout) of
                    ?OK ->
                        KeydirUser = keydir_util:read_user(Transport, Timeout),
                        {ok, KeydirUser};
                    ?ERROR ->
                        Reason = keydir_util:read_binary(2, Transport, Timeout),
                        {error, Reason}
                end
            catch
                throw:{keydir_util, KeydirUtilReason} ->
                    close(Transport),
                    {error, KeydirUtilReason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% Exported: update

-spec update(#keydir_user{}, #keydir_network_client_options{}, timeout()) ->
          ok | {error, any()}.

update(KeydirUser, Options, Timeout) ->
    ?dbg_log({update, KeydirUser, Timeout, Options}),
    case connect(Timeout, Options)  of
        {ok, Transport} ->
            try
                ok = keydir_util:write_integer(1, Transport, ?UPDATE),
                ok = keydir_util:write_user(Transport, KeydirUser),
                case keydir_util:read_integer(1, Transport, Timeout) of
                    ?OK ->
                        ok;
                    ?ERROR ->
                        Reason = keydir_util:read_binary(2, Transport, Timeout),
                        {error, Reason}
                end
            catch
                throw:{keydir_util, KeydirUtilReason} ->
                    close(Transport),
                    {error, KeydirUtilReason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% Exported: delete

-spec delete(binary(), binary(), #keydir_network_client_options{}, timeout()) ->
          ok | {error, any()}.

delete(Name, Password, Options, Timeout) ->
    ?dbg_log({delete, Name, Password, Timeout, Options}),
    case connect(Timeout, Options) of
        {ok, Transport} ->
            try
                ok = keydir_util:write_integer(1, Transport, ?DELETE),
                ok = keydir_util:write_binary(1, Transport, Name),
                ok = keydir_util:write_binary(1, Transport, Password),
                case keydir_util:read_integer(1, Transport, Timeout) of
                    ?OK ->
                        ok;
                    ?ERROR ->
                        Reason = keydir_util:read_binary(2, Transport, Timeout),
                        {error, Reason}
                end
            catch
                throw:{keydir_util, KeydirUtilReason} ->
                    close(Transport),
                    {error, KeydirUtilReason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% Exported: alive

-spec alive(transport(), timeout()) -> boolean().

alive(Transport, Timeout) ->
    ?dbg_log(ping),
    try
        ok = keydir_util:write_integer(1, Transport, ?PING),
        ?PONG = keydir_util:read_integer(1, Transport, Timeout),
        ?dbg_log(pong),
        true
    catch
        throw:{keydir_util, _Reason} ->
            false
    end.

%%
%% Transport primitives
%%

connect(Timeout, Options) ->
    Transport = get(keydir_transport),
    case Transport /= undefined andalso alive(Transport, Timeout) of
        true ->
            {ok, Transport};
        false ->
            case Options of
                #keydir_network_client_options{
                   keydir_access = {tor_only, {OnionAddress, Port}}} ->
                    case tor_socks_tcp:connect(
                           OnionAddress, Port, [binary, {active, false}],
                           Timeout) of
                        {ok, Pid} ->
                            NewTransport = {socks, Pid},
                            put(keydir_transport, NewTransport),
                            {ok, NewTransport};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                #keydir_network_client_options{
                   keydir_access = {tcp_only, {IpAddress, Port}}} ->
                    case gen_tcp:connect(
                           IpAddress, Port, [binary, {active, false}],
                           Timeout) of
                        {ok, Socket} ->
                            NewTransport = Socket,
                            put(keydir_transport, NewTransport),
                            {ok, NewTransport};
                        {error, Reason} ->
                            {error, Reason}
                    end;
                #keydir_network_client_options{
                   keydir_access = {tor_fallback_to_tcp,
                                 {OnionAddress, OnionPort},
                                 {IpAddress, TcpPort}}} ->
                    case tor_socks_tcp:connect(
                           OnionAddress, OnionPort, [binary, {active, false}],
                           Timeout) of
                        {ok, Pid} ->
                            NewTransport = {socks, Pid},
                            put(keydir_transport, NewTransport),
                            {ok, NewTransport};
                        {error, _Reason} ->
                            case gen_tcp:connect(
                                   IpAddress, TcpPort,
                                   [binary, {active, false}], Timeout) of
                                {ok, Socket} ->
                                    NewTransport = Socket,
                                    put(keydir_transport, NewTransport),
                                    ?daemon_log_tag_fmt(
                                       system,
                                       "WARNING: Falls back to TCP access",
                                       []),
                                    {ok, NewTransport};
                                {error, Reason} ->
                                    {error, Reason}
                            end
                    end
            end
    end.

close({socks, Pid}) ->
    erase(keydir_transport),
    tor_socks_tcp:close(Pid);
close(Socket) ->
    erase(keydir_transport),
    gen_tcp:close(Socket).

%% Exported: recv

-spec recv(transport(), integer(), timeout()) ->
          {ok, binary()} | {error, any()}.

recv({socks, Pid}, Length, Timeout) ->
    tor_socks_tcp:recv(Pid, Length, Timeout);
recv(Socket, Length, Timeout) ->
    gen_tcp:recv(Socket, Length, Timeout).

%% Exported: send

-spec send(transport(), binary()) -> ok | {error, any()}.

send({socks, Pid}, Packet) ->
    tor_socks_tcp:send(Pid, Packet);
send(Socket, Packet) ->
    gen_tcp:send(Socket, Packet).
