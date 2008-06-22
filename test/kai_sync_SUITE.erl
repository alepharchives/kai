% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License.  You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
% License for the specific language governing permissions and limitations under
% the License.

-module(kai_sync_SUITE).
-compile(export_all).

-include("kai.hrl").
-include("kai_test.hrl").

all() -> [test1].

test1_api_proc(ApiSocket) ->
    receive
	{tcp, ApiSocket, Bin} ->
	    case binary_to_term(Bin) of
		{list, 0 = _Bucket} ->
		    Metadata = [#metadata{key=("item-4"), bucket=3, last_modified=now(),
					  checksum=erlang:md5(<<"item-4">>)}],
		    gen_tcp:send(ApiSocket, term_to_binary({metadata, Metadata}));
		{list, 3 = _Bucket} ->
		    Metadata = [#metadata{key=("item-1"), bucket=3, last_modified=now(),
					  checksum=erlang:md5(<<"item-1">>)},
				#metadata{key=("item-3"), bucket=3, last_modified=now(),
					  checksum=erlang:md5(<<"item-3">>)}],
		    gen_tcp:send(ApiSocket, term_to_binary({metadata, Metadata}));

		{get, "item-3"} ->
		    Data = #data{key="item-3", bucket=3, last_modified=now(),
				 checksum=erlang:md5(<<"value-3">>), flags="0", value=(<<"value-3">>)},
		    gen_tcp:send(ApiSocket, term_to_binary(Data));
		{get, "item-4"} ->
		    Data = #data{key="item-4", bucket=0, last_modified=now(),
				 checksum=erlang:md5(<<"value-4">>), flags="0", value=(<<"value-4">>)},
		    gen_tcp:send(ApiSocket, term_to_binary(Data))
	    end,
            test1_api_proc(ApiSocket)
    end.

test1_api_accpet(ListeningSocket) ->
    {ok, ApiSocket} = gen_tcp:accept(ListeningSocket),
    Pid = spawn(?MODULE, test1_api_proc, [ApiSocket]),
    gen_tcp:controlling_process(ApiSocket, Pid),
    test1_api_accpet(ListeningSocket).
	
test1_api_start() ->
    {ok, ListeningSocket} =
	gen_tcp:listen(11012, [binary, {packet, 4}, {reuseaddr, true}]),
    test1_api_accpet(ListeningSocket).

test1() -> [].
test1(_Conf) ->
    kai_config:start_link([{hostname, "localhost"}, {port, 11011}, {n, 3},
			   {number_of_buckets, 8},
			   {number_of_virtual_nodes, 2}]),
    kai_hash:start_link(),
    kai_store:start_link(),
    kai_sync:start_link(),

    {replaced_buckets, _ReplacedBuckets} =
	kai_hash:update_nodes([{?NODE2, ?INFO}], []),

    Data1 = #data{key=("item-1"), bucket=3, last_modified=now(),
		  checksum=erlang:md5(<<"value-1">>), flags="0", value=(<<"value-1">>)},
    kai_store:put(Data1),

    spawn_link(?MODULE, test1_api_start, []),

    kai_sync:update_bucket(3),

    timer:sleep(100),

    {metadata, Metadata} = kai_store:list(3),
    ?assertEqual(2, length(Metadata)),
    ?assert(lists:keymember("item-3", 2, Metadata)),

    kai_sync:delete_bucket(3),

    timer:sleep(100),

    {metadata, Metadata2} = kai_store:list(3),
    ?assertEqual(0, length(Metadata2)),

    timer:sleep(1100), % timeout and update bucket-0 by kai_hash:choose_bucket_randomly/0

    {metadata, Metadata3} = kai_store:list(0),
    ?assertEqual(1, length(Metadata3)),
    ?assert(lists:keymember("item-4", 2, Metadata3)),

    kai_sync:stop(),
    kai_store:stop(),
    kai_hash:stop(),
    kai_config:stop().
