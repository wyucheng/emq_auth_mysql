%%--------------------------------------------------------------------
%% Copyright (c) 2012-2016 Feng Lee <feng@emqtt.io>.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

%% @doc MySQL Authentication/ACL Client
-module(emq_auth_mysql_cli).

-behaviour(ecpool_worker).

-include("emq_auth_mysql.hrl").

-include_lib("emqttd/include/emqttd.hrl").

-export([is_superuser/2, parse_query/1, connect/1, query/3, insert/3]).

%%--------------------------------------------------------------------
%% Is Superuser?
%%--------------------------------------------------------------------

-spec(is_superuser(undefined | {string(), list()}, mqtt_client()) -> boolean()).
is_superuser(undefined, _Client) ->
    false;
is_superuser({SuperSql, Params}, Client) ->
    case query(SuperSql, Params, Client) of
        {ok, [_Super], [[1]]} ->
            true;
        {ok, [_Super], [[_False]]} ->
            false;
        {ok, [_Super], []} ->
            false;
        {error, _Error} ->
            false
    end.

%%--------------------------------------------------------------------
%% Avoid SQL Injection: Parse SQL to Parameter Query.
%%--------------------------------------------------------------------

parse_query(undefined) ->
    undefined;
parse_query(Sql) ->
    case re:run(Sql, "'%[ucatpw]'", [global, {capture, all, list}]) of
        {match, Variables} ->
            Params = [Var || [Var] <- Variables],
            {re:replace(Sql, "'%[ucatpw]'", "?", [global, {return, list}]), Params};
        nomatch ->
            {Sql, []}
    end.

%%--------------------------------------------------------------------
%% MySQL Connect/Query
%%--------------------------------------------------------------------

connect(Options) ->
    mysql:start_link(Options).

query(Sql, Params, Client) ->
    ecpool:with_client(?APP, fun(C) -> mysql:query(C, Sql, replvar(Params, Client)) end).

insert(Sql, Params, Message) ->
    ecpool:with_client(?APP, fun(C) -> mysql:query(C, Sql, replvar_topic(Params, Message)) end).

% acl
replvar(Params, Client) ->
    replvar(Params, Client, []).

replvar([], _Client, Acc) ->
    lists:reverse(Acc);
replvar(["'%u'" | Params], Client = #mqtt_client{username = Username}, Acc) ->
    replvar(Params, Client, [Username | Acc]);
replvar(["'%c'" | Params], Client = #mqtt_client{client_id = ClientId}, Acc) ->
    replvar(Params, Client, [ClientId | Acc]);
replvar(["'%a'" | Params], Client = #mqtt_client{peername = {IpAddr, _}}, Acc) ->
    replvar(Params, Client, [inet_parse:ntoa(IpAddr) | Acc]);
replvar([Param | Params], Client, Acc) ->
    replvar(Params, Client, [Param | Acc]).

% topic
replvar_topic(Params, Message) ->
    replvar_topic(Params, Message, []).

replvar_topic([], _Message, Acc) ->
    lists:reverse(Acc);
replvar_topic(["'%c'" | Params], Message = #mqtt_message{from = {ClientId, _Username}}, Acc) ->
    replvar_topic(Params, Message, [ClientId | Acc]);
replvar_topic(["'%t'" | Params], Message = #mqtt_message{topic = Topic}, Acc) ->
    replvar_topic(Params, Message, [Topic | Acc]);
replvar_topic(["'%p'" | Params], Message = #mqtt_message{payload = Payload}, Acc) ->
    replvar_topic(Params, Message, [Payload | Acc]);
replvar_topic(["'%w'" | Params], Message = #mqtt_message{timestamp = Timestamp}, Acc) ->
    replvar_topic(Params, Message, [Timestamp | Acc]);
replvar_topic([Param | Params], Message, Acc) ->
    replvar_topic(Params, Message, [Param | Acc]).