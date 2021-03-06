%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License.  You may obtain a copy of
%% the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
%% License for the specific language governing permissions and limitations under
%% the License.

-module(kai_tcp_server_SUITE).
-compile(export_all).
-export([init/1, handle_call/3]). %% For echo server

-include("ct.hrl").
-include("kai.hrl").
-include("kai_test.hrl").

sequences() ->
    [{seq, [single_connection, error_and_reboot, multiple_connections,
            connection_counter]}].

all() -> [{sequence, seq}].

init_per_testcase(connection_counter, Config) ->
    start_server(10),
    Config;
init_per_testcase(_TestCase, Config) ->
    start_server(1),
    Config.

start_server(MaxProcesses) ->
    kai_tcp_server:start_link(
        ?MODULE, [], #tcp_server_option{max_processes=MaxProcesses}
    ).

end_per_testcase(_TestCase, _Config) ->
    kai_tcp_server:stop().

single_connection(_Conf) ->
    normal_procedure().

normal_procedure() ->
    {ok, Socket} = connect_to_echo_server(),
    gen_tcp:send(Socket, <<"hello\r\n">>),
    case gen_tcp:recv(Socket, 0) of
       {ok, <<"hello\r\n">>} -> ok;
       _HelloError           -> ct:fail(bad_echo_value)
    end,
    gen_tcp:send(Socket, <<"bye\r\n">>),
    case gen_tcp:recv(Socket, 0) of
       {ok, <<"cya\r\n">>} -> ok;
       _ByeError           -> ct:fail(bad_return_value)
    end,
    gen_tcp:close(Socket).

error_and_reboot(_Conf) ->
    {ok, Socket} = connect_to_echo_server(),
    gen_tcp:send(Socket, <<"error\r\n">>),
    {error, closed} = gen_tcp:recv(Socket, 0),
    gen_tcp:close(Socket),
    normal_procedure(). %% Check whether the echo server has rebooted

multiple_connections(_Conf) ->
    lists:foreach(fun (_N) ->
        {ok, Socket} = connect_to_echo_server(),
        gen_tcp:close(Socket)
    end, lists:seq(1, 1024)).

connection_counter(_Conf) ->
    Sockets = lists:map(fun (_N) ->
        {ok, Socket} = connect_to_echo_server(),
        Socket
    end, lists:seq(1, 5)),
    timer:sleep(100), %% Wait for increment
    case kai_tcp_server:info(curr_connections) of
        5 -> ok;
        Error ->
            ct:comment(io:format("bad_info:~p", [Error])),
            ct:fail(bad_info)
    end,
    lists:foreach(fun (Socket) -> gen_tcp:close(Socket) end, Sockets).

connect_to_echo_server() ->
    gen_tcp:connect(
        {127,0,0,1}, 11211, [binary, {packet, line}, {active, false}]
    ).

%% Echo server
init(_Args) -> {ok, {}}.

handle_call(_Socket, <<"bye\r\n">>, State) ->
    {close, <<"cya\r\n">>, State};
handle_call(_Socket, <<"error\r\n">>, State) ->
    (fun(X) -> 1 / X end)(0), %% Always throws a bad arithmetic exception
    {close, <<"error\r\n">>, State};
handle_call(_Socket, Data, State) ->
    {reply, Data, State}.
