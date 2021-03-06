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

-module(kai_version).
-behaviour(gen_server).

-export([start_link/0, stop/0]).
-export([update/1, order/1, cas_unique/1]).
-export([
         init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2,
         code_change/3
        ]).

-include("kai.hrl").

-define(SERVER, ?MODULE).
-define(CAS_UNIQUE_BITS, 64).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], _Opts = []).

init(_Args) ->
    {ok, []}.

terminate(_Reason, _State) ->
    ok.

update(Data, State) ->
    NewDataVClock = vclock:increment(kai_config:get(node), Data#data.vector_clocks),
    {reply,
     {ok, Data#data{last_modified=now(), vector_clocks=NewDataVClock}}, State }.

do_order([], []) ->
    undefined;
do_order([], UniqList) ->
    UniqList;
do_order([Data|Rest], UniqList) ->
    VClock = Data#data.vector_clocks,
    Comp = fun(Other) -> vclock:descends(Other#data.vector_clocks, VClock) end,
    case lists:any(Comp, Rest) of
        true ->
            do_order(Rest, UniqList);
        _ ->
            Comp2 = fun(Other) -> vclock:descends(Other#data.vector_clocks, VClock) end,
            case lists:any(Comp2, UniqList) of
                true ->
                    do_order(Rest, UniqList);
                _ ->
                    do_order(Rest, [Data|UniqList])
            end
    end.

order(DataList, State) when is_list(DataList) ->
    OrderedData = do_order(DataList, []),
    {reply, OrderedData, State};
order(_Other, State) ->
    {reply, undefined, State}.


%% TODO: raise error if length > 15(=2#1111)
cas_unique(DataList) when length(DataList) > 2#1111 ->
    {error, lists:flatten(io_lib:format("data list is too long (~p)", [length(DataList)]))};
cas_unique(DataList) ->
    Length = length(DataList),
    EachBits = trunc(60/Length),
    %% TODO: make 128 contant 2008/11/06 by shino
    RestBits = 128- EachBits,
    cas_unique(lists:map(fun (Data) ->
                                 <<CheckSum:EachBits, _:RestBits>> = Data#data.checksum,
                                 CheckSum
                         end, DataList),
               EachBits,
               Length,
               4).

cas_unique([], _EachBits, Result, ResultBits) ->
    BitsToBePadded = ?CAS_UNIQUE_BITS- ResultBits,
    {ok, <<Result:ResultBits, 0:BitsToBePadded>>};
cas_unique([CheckSum | RestCS], EachBits, Result, ResultBits) ->
    ResultBits2 = ResultBits + EachBits,
    <<Result2:ResultBits2>> = <<Result:ResultBits, CheckSum:EachBits>>,
    cas_unique(RestCS, EachBits, Result2, ResultBits2).

handle_call(stop, _From, State) ->
    {stop, normal, stopped, State};
handle_call({update, Data}, _From, State) ->
    update(Data, State);
handle_call({order, DataList}, _From, State) ->
    order(DataList, State).
handle_cast(_Msg, State) ->
    {noreply, State}.
handle_info(_Info, State) ->
    {noreply, State}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

stop() ->
    gen_server:call(?SERVER, stop).
update(Data) ->
    gen_server:call(?SERVER, {update, Data}).
order(DataList) ->
    gen_server:call(?SERVER, {order, DataList}).
