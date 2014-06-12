%-*-Mode:erlang;coding:utf-8;tab-width:4;c-basic-offset:4;indent-tabs-mode:()-*-
% ex: set ft=erlang fenc=utf-8 sts=4 ts=4 sw=4 et:
%%%
%%%------------------------------------------------------------------------
%%% @doc
%%% ==Riak CloudI Service==
%%% @end
%%%
%%% BSD LICENSE
%%% 
%%% Copyright (c) 2014, Michael Truog <mjtruog at gmail dot com>
%%% All rights reserved.
%%% 
%%% Redistribution and use in source and binary forms, with or without
%%% modification, are permitted provided that the following conditions are met:
%%% 
%%%     * Redistributions of source code must retain the above copyright
%%%       notice, this list of conditions and the following disclaimer.
%%%     * Redistributions in binary form must reproduce the above copyright
%%%       notice, this list of conditions and the following disclaimer in
%%%       the documentation and/or other materials provided with the
%%%       distribution.
%%%     * All advertising materials mentioning features or use of this
%%%       software must display the following acknowledgment:
%%%         This product includes software developed by Michael Truog
%%%     * The name of the author may not be used to endorse or promote
%%%       products derived from this software without specific prior
%%%       written permission
%%% 
%%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
%%% CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
%%% INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
%%% OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
%%% DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
%%% CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
%%% SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
%%% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
%%% SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
%%% INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
%%% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
%%% NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
%%% OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
%%% DAMAGE.
%%%
%%% @author Michael Truog <mjtruog [at] gmail (dot) com>
%%% @copyright 2014 Michael Truog
%%% @version 1.3.3 {@date} {@time}
%%%------------------------------------------------------------------------

-module(cloudi_service_db_riak).
-author('mjtruog [at] gmail (dot) com').

-behaviour(cloudi_service).

%% external interface
-export([new/5,
         new/6,
         delete/4,
         delete/5,
         get/4,
         get/5,
         get_index_eq/5,
         get_index_eq/6,
         get_index_range/6,
         get_index_range/7,
         put/4,
         put/5,
         put/6,
         object/2,
         object/3,
         object/4]).

%% cloudi_service callbacks
-export([cloudi_service_init/3,
         cloudi_service_handle_request/11,
         cloudi_service_handle_info/3,
         cloudi_service_terminate/2]).

-include_lib("cloudi_core/include/cloudi_logger.hrl").

-define(DEFAULT_HOST_NAME,                  "127.0.0.1").
-define(DEFAULT_PORT,                              8087).
-define(DEFAULT_OPTIONS,                             []).
-define(DEFAULT_PING,                         undefined). % ms
-define(DEFAULT_BUCKET,                       undefined). % lock to bucket

-record(state,
    {
        connection :: pid(),
        prefix_length :: pos_integer()
    }).

% from riakc.hrl
-record(index_results_v1,
    {
        keys :: list(binary()) | undefined,
        terms :: list({integer() | binary(), binary()}) | undefined,
        continuation :: binary() | undefined
    }).

%%%------------------------------------------------------------------------
%%% External interface functions
%%%------------------------------------------------------------------------

-type dispatcher() :: cloudi_service:dispatcher() | cloudi:context().
-type riakc_obj() :: riakc_obj:riakc_obj().
-type index_id() :: {binary_index, string()} | {integer_index, string()}.
-type indexes() :: list({{binary_index, string()}, list(binary())} |
                        {{integer_index, string()}, list(integer())}).
-type new_options() :: list({content_type, string() | undefined} |
                            {object, boolean()} |
                            {indexes, indexes()} |
                            % from put_option() in riakc.hrl
                            {atom(), any()} | atom()).
-type delete_options() :: list(% from delete_option() in riakc.hrl
                               {atom(), any()} | atom()).
-type get_options() :: list({object, boolean()} |
                            % from get_option() in riakc.hrl
                            {atom(), any()} | atom()).
-type get_index_eq_options() :: list(% from index_opts()
                                     % in riakc_pb_socket.erl
                                     {atom(), any()}).
-type get_index_range_options() :: list(% from range_index_opts()
                                        % in riakc_pb_socket.erl
                                        {atom(), any()}).
-type put_options() :: list({content_type, string() | undefined} |
                            {object, boolean()} |
                            {indexes, indexes()} |
                            % from put_option() in riakc.hrl
                            {atom(), any()} | atom()).
-export_type([riakc_obj/0, index_id/0, indexes/0]).

%%-------------------------------------------------------------------------
%% @doc
%% ===Create a new key/value pair in a bucket.===
%% @end
%%-------------------------------------------------------------------------

-spec new(Dispatcher :: dispatcher(),
          Name :: cloudi_service:service_name(),
          Key :: binary() | undefined,
          Value :: binary(),
          Timeout :: cloudi_service:timeout_milliseconds()) ->
    {ok, Key :: binary(), NewValue :: binary()} |
    {siblings, Key :: binary(), Values :: list(binary())} |
    {error, cloudi_service:error_reason_sync() | no_value | any()}.

new(Dispatcher, Name, Key, Value, Timeout) ->
    case cloudi:send_sync(Dispatcher, Name,
                          {new, Key, Value, []}, Timeout) of
        {ok, {ok, _, _} = Success} ->
            Success;
        {ok, {siblings, _, _} = Success} ->
            Success;
        {ok, {error, _} = Error} ->
            Error;
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Create a new key/value pair with options in a bucket.===
%% @end
%%-------------------------------------------------------------------------

-spec new(Dispatcher :: dispatcher(),
          Name :: cloudi_service:service_name(),
          Key :: binary() | undefined,
          Value :: binary(),
          Options :: new_options(),
          Timeout :: cloudi_service:timeout_milliseconds()) ->
    {ok, Key :: binary(), NewValueOrObject :: binary() | riakc_obj()} |
    {siblings, Key :: binary(), Values :: list(binary())} |
    {error, cloudi_service:error_reason_sync() | no_value | any()}.

new(Dispatcher, Name, Key, Value, Options, Timeout) ->
    case cloudi:send_sync(Dispatcher, Name,
                          {new, Key, Value, Options}, Timeout) of
        {ok, {ok, _, _} = Success} ->
            Success;
        {ok, {siblings, _, _} = Success} ->
            Success;
        {ok, {error, _} = Error} ->
            Error;
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Delete a key/value pair in a bucket.===
%% @end
%%-------------------------------------------------------------------------

-spec delete(Dispatcher :: dispatcher(),
             Name :: cloudi_service:service_name(),
             KeyOrObject :: binary() | riakc_obj(),
             Timeout :: cloudi_service:timeout_milliseconds()) ->
    ok |
    {error, cloudi_service:error_reason_sync() | any()}.

delete(Dispatcher, Name, KeyOrObject, Timeout) ->
    delete(Dispatcher, Name, KeyOrObject, [], Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Delete a key/value pair in a bucket with options.===
%% @end
%%-------------------------------------------------------------------------

-spec delete(Dispatcher :: dispatcher(),
             Name :: cloudi_service:service_name(),
             KeyOrObject :: binary() | riakc_obj(),
             Options :: delete_options(),
             Timeout :: cloudi_service:timeout_milliseconds()) ->
    ok |
    {error, cloudi_service:error_reason_sync() | any()}.

delete(Dispatcher, Name, KeyOrObject, Options, Timeout) ->
    case cloudi:send_sync(Dispatcher, Name,
                          {delete, KeyOrObject, Options}, Timeout) of
        {ok, ok} ->
            ok;
        {ok, {error, _} = Error} ->
            Error;
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Retrieve a key/value pair from a bucket.===
%% @end
%%-------------------------------------------------------------------------

-spec get(Dispatcher :: dispatcher(),
          Name :: cloudi_service:service_name(),
          KeyOrObject :: binary() | riakc_obj(),
          Timeout :: cloudi_service:timeout_milliseconds()) ->
    {ok, Key :: binary(), ValueOrObject :: binary() | riakc_obj()} |
    {siblings, Key :: binary(), Values :: list(binary())} |
    {error, cloudi_service:error_reason_sync() | no_value | any()}.

get(_Dispatcher, _Name, Object, _Timeout)
    when is_tuple(Object) ->
    object_to_tuple(Object);
get(Dispatcher, Name, Key, Timeout) ->
    get(Dispatcher, Name, Key, [], Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Retrieve a key/value pair from a bucket with options.===
%% @end
%%-------------------------------------------------------------------------

-spec get(Dispatcher :: dispatcher(),
          Name :: cloudi_service:service_name(),
          Key :: binary(),
          Options :: get_options(),
          Timeout :: cloudi_service:timeout_milliseconds()) ->
    {ok, Key :: binary(), ValueOrObject :: binary() | riakc_obj()} |
    {siblings, Key :: binary(), Values :: list(binary())} |
    {error, cloudi_service:error_reason_sync() | no_value | any()}.

get(Dispatcher, Name, Key, Options, Timeout) ->
    case cloudi:send_sync(Dispatcher, Name,
                          {get, Key, Options}, Timeout) of
        {ok, {ok, _, _} = Success} ->
            Success;
        {ok, {siblings, _, _} = Success} ->
            Success;
        {ok, {error, _} = Error} ->
            Error;
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Get a secondary index equality query.===
%% @end
%%-------------------------------------------------------------------------

-spec get_index_eq(Dispatcher :: dispatcher(),
                   Name :: cloudi_service:service_name(),
                   Index :: index_id() | binary(),
                   Key :: binary() | integer(),
                   Timeout :: cloudi_service:timeout_milliseconds()) ->
    {ok, Keys :: list(binary()),
         Terms :: list({integer() | binary(), binary()}),
         Continuation :: binary()} |
    {error, cloudi_service:error_reason_sync() | any()}.

get_index_eq(Dispatcher, Name, Index, Key, Timeout) ->
    get_index_eq(Dispatcher, Name, Index, Key, [], Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Get a secondary index equality query with options.===
%% @end
%%-------------------------------------------------------------------------

-spec get_index_eq(Dispatcher :: dispatcher(),
                   Name :: cloudi_service:service_name(),
                   Index :: index_id() | binary(),
                   Key :: binary() | integer(),
                   Options :: get_index_eq_options(),
                   Timeout :: cloudi_service:timeout_milliseconds()) ->
    {ok, Keys :: list(binary()),
         Terms :: list({integer() | binary(), binary()}),
         Continuation :: binary()} |
    {error, cloudi_service:error_reason_sync() | any()}.

get_index_eq(Dispatcher, Name, Index, Key, Options, Timeout) ->
    case cloudi:send_sync(Dispatcher, Name,
                          {get_index_eq, Index, Key, Options}, Timeout) of
        {ok, {ok, _, _, _} = Success} ->
            Success;
        {ok, {error, _} = Error} ->
            Error;
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Get a secondary index range query.===
%% @end
%%-------------------------------------------------------------------------

-spec get_index_range(Dispatcher :: dispatcher(),
                      Name :: cloudi_service:service_name(),
                      Index :: index_id() | binary(),
                      KeyStart :: binary() | integer() | list(),
                      KeyEnd :: binary() | integer() | list(),
                      Timeout :: cloudi_service:timeout_milliseconds()) ->
    {ok, Keys :: list(binary()),
         Terms :: list({integer() | binary(), binary()}),
         Continuation :: binary()} |
    {error, cloudi_service:error_reason_sync() | any()}.

get_index_range(Dispatcher, Name, Index, KeyStart, KeyEnd, Timeout) ->
    get_index_range(Dispatcher, Name, Index, KeyStart, KeyEnd, [], Timeout).

%%-------------------------------------------------------------------------
%% @doc
%% ===Get a secondary index range query with options.===
%% @end
%%-------------------------------------------------------------------------

-spec get_index_range(Dispatcher :: dispatcher(),
                      Name :: cloudi_service:service_name(),
                      Index :: index_id() | binary(),
                      KeyStart :: binary() | integer() | list(),
                      KeyEnd :: binary() | integer() | list(),
                      Options :: get_index_range_options(),
                      Timeout :: cloudi_service:timeout_milliseconds()) ->
    {ok, Keys :: list(binary()),
         Terms :: list({integer() | binary(), binary()}),
         Continuation :: binary()} |
    {error, cloudi_service:error_reason_sync() | any()}.

get_index_range(Dispatcher, Name, Index, KeyStart, KeyEnd, Options, Timeout) ->
    case cloudi:send_sync(Dispatcher, Name,
                          {get_index_range, Index,
                           KeyStart, KeyEnd, Options}, Timeout) of
        {ok, {ok, _, _, _} = Success} ->
            Success;
        {ok, {error, _} = Error} ->
            Error;
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Store a key/value pair in a bucket.===
%% @end
%%-------------------------------------------------------------------------

-spec put(Dispatcher :: dispatcher(),
          Name :: cloudi_service:service_name(),
          Object :: riakc_obj(),
          Timeout :: cloudi_service:timeout_milliseconds()) ->
    {ok, Key :: binary(), Object :: riakc_obj()} |
    {error, cloudi_service:error_reason_sync() | no_value | any()}.

put(Dispatcher, Name, Object, Timeout) ->
    case cloudi:send_sync(Dispatcher, Name,
                          {put, riakc_obj:key(Object), Object,
                           [{object, true}]}, Timeout) of
        {ok, {ok, _, _} = Success} ->
            Success;
        {ok, {error, _} = Error} ->
            Error;
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Store a key/value pair in a bucket.===
%% @end
%%-------------------------------------------------------------------------

-spec put(Dispatcher :: dispatcher(),
          Name :: cloudi_service:service_name(),
          Key :: binary(),
          ValueOrObject :: binary() | riakc_obj(),
          Timeout :: cloudi_service:timeout_milliseconds()) ->
    {ok, Key :: binary(), Value :: binary()} |
    {siblings, Key :: binary(), Values :: list(binary())} |
    {error, cloudi_service:error_reason_sync() | no_value | any()}.

put(Dispatcher, Name, Key, ValueOrObject, Timeout) ->
    case cloudi:send_sync(Dispatcher, Name,
                          {put, Key, ValueOrObject, []}, Timeout) of
        {ok, {ok, _, _} = Success} ->
            Success;
        {ok, {siblings, _, _} = Success} ->
            Success;
        {ok, {error, _} = Error} ->
            Error;
        {error, _} = Error ->
            Error
    end.

%%-------------------------------------------------------------------------
%% @doc
%% ===Store a key/value pair in a bucket with options.===
%% @end
%%-------------------------------------------------------------------------

-spec put(Dispatcher :: dispatcher(),
          Name :: cloudi_service:service_name(),
          Key :: binary(),
          ValueOrObject :: binary() | riakc_obj(),
          Options :: put_options(),
          Timeout :: cloudi_service:timeout_milliseconds()) ->
    {ok, Key :: binary(), ValueOrObject :: binary() | riakc_obj()} |
    {siblings, Key :: binary(), Values :: list(binary())} |
    {error, cloudi_service:error_reason_sync() | no_value | any()}.

put(Dispatcher, Name, Key, ValueOrObject, Options, Timeout) ->
    case cloudi:send_sync(Dispatcher, Name,
                          {put, Key, ValueOrObject, Options}, Timeout) of
        {ok, {ok, _, _} = Success} ->
            Success;
        {ok, {siblings, _, _} = Success} ->
            Success;
        {ok, {error, _} = Error} ->
            Error;
        {error, _} = Error ->
            Error
    end.

-spec object(F :: atom(),
             Arg1 :: riakc_obj()) ->
    any().

object(F, Arg1) when is_atom(F) ->
    riakc_obj:F(Arg1).

-spec object(F :: atom(),
             Arg1 :: riakc_obj() | any(),
             Arg2 :: riakc_obj() | any()) ->
    any().

object(F, Arg1, Arg2) when is_atom(F) ->
    riakc_obj:F(Arg1, Arg2).

-spec object(F :: atom(),
             Arg1 :: riakc_obj() | any(),
             Arg2 :: riakc_obj() | any(),
             Arg3 :: riakc_obj() | any()) ->
    any().

object(F, Arg1, Arg2, Arg3) when is_atom(F) ->
    riakc_obj:F(Arg1, Arg2, Arg3).

%%%------------------------------------------------------------------------
%%% Callback functions from cloudi_service
%%%------------------------------------------------------------------------

cloudi_service_init(Args, Prefix, Dispatcher) ->
    Defaults = [
        {hostname,                       ?DEFAULT_HOST_NAME},
        {port,                           ?DEFAULT_PORT},
        {options,                        ?DEFAULT_OPTIONS},
        {ping,                           ?DEFAULT_PING},
        {bucket,                         ?DEFAULT_BUCKET}],
    [HostName, Port, Options, Ping, Bucket] =
        cloudi_proplists:take_values(Defaults, Args),
    true = is_list(HostName),
    true = is_integer(Port),
    true = is_list(Options),
    TimeoutMax = cloudi_service:timeout_max(Dispatcher),
    if
        Ping =:= undefined ->
            ok;
        is_integer(Ping), Ping > 0, Ping =< TimeoutMax ->
            erlang:send_after(Ping, cloudi_service:self(Dispatcher),
                              {ping, Ping})
    end,
    if
        Bucket =:= undefined ->
            cloudi_service:subscribe(Dispatcher, "*");
        is_list(Bucket), is_integer(hd(Bucket)) ->
            cloudi_service:subscribe(Dispatcher, Bucket)
    end,
    case riakc_pb_socket:start_link(HostName, Port, Options) of
        {ok, Connection} ->
            State = #state{connection = Connection,
                           prefix_length = erlang:length(Prefix)},
            % starting state needs to be connected,
            % irregardless of auto_connect, to fail-fast
            case riakc_pb_socket:is_connected(Connection) of
                true ->
                    {ok, State};
                {false, Reason} ->
                    {stop, {disconnected, Reason}, State}
            end;
        {error, _} = Error ->
            {stop, Error}
    end.

cloudi_service_handle_request(_Type, Name, _Pattern, _RequestInfo, Request,
                              Timeout, _Priority, _TransId, _Pid,
                              #state{connection = Connection,
                                     prefix_length = PrefixLength} = State,
                              _Dispatcher) ->
    Bucket = erlang:list_to_binary(lists:nthtail(PrefixLength, Name)),
    case Request of
        {new, Key, Value, Options0}
            when (Key =:= undefined) orelse is_binary(Key),
                 is_binary(Value), is_list(Options0) ->
            Defaults = [
                {content_type, undefined},
                {object, false},
                {indexes, []}],
            [ContentType, ObjectReply, Indexes | Options1] =
                cloudi_proplists:take_values(Defaults, Options0),
            Object0 = if
                ContentType =:= undefined ->
                    riakc_obj:new(Bucket, Key, Value);
                is_list(ContentType), is_integer(hd(ContentType)) ->
                    riakc_obj:new(Bucket, Key, Value, ContentType)
            end,
            Object1 = object_indexes(Object0, Indexes),
            OptionsN = if
                Key =:= undefined ->
                    [return_body | Options1];
                true ->
                    Options1
            end,
            Response = case riakc_pb_socket:put(Connection, Object1,
                                                OptionsN, Timeout) of
                ok ->
                    if
                        ObjectReply =:= true ->
                            {ok, Key, Object1};
                        ObjectReply =:= false ->
                            object_to_tuple(Object1)
                    end;
                {ok, ObjectN} ->
                    if
                        ObjectReply =:= true ->
                            {ok, riakc_obj:key(ObjectN), ObjectN};
                        ObjectReply =:= false ->
                            object_to_tuple(ObjectN)
                    end;
                {error, _} = Error ->
                    Error
            end,
            {reply, Response, State};
        {delete, Key, Options}
            when is_binary(Key), is_list(Options) ->
            Response = riakc_pb_socket:delete(Connection, Bucket, Key,
                                              Options, Timeout),
            {reply, Response, State};
        {delete, Object, Options}
            when is_tuple(Object), is_list(Options) ->
            Response = riakc_pb_socket:delete(Connection, Bucket,
                                              riakc_obj:key(Object),
                                              Options, Timeout),
            {reply, Response, State};
        {get, Key, Options0}
            when is_binary(Key), is_list(Options0) ->
            Defaults = [
                {object, false}],
            [ObjectReply | OptionsN] =
                cloudi_proplists:take_values(Defaults, Options0),
            Response = case riakc_pb_socket:get(Connection, Bucket, Key,
                                                OptionsN, Timeout) of
                {ok, Object} ->
                    if
                        ObjectReply =:= true ->
                            {ok, riakc_obj:key(Object), Object};
                        ObjectReply =:= false ->
                            object_to_tuple(Object)
                    end;
                {error, _} = Error ->
                    Error
            end,
            {reply, Response, State};
        {get_index_eq, Index, Key, Options0} ->
            Options1 = [{timeout, Timeout},
                        {call_timeout, Timeout + 100} | Options0],
            Response = case riakc_pb_socket:get_index_eq(Connection,
                                                         Bucket, Index, Key,
                                                         Options1) of
                {ok, #index_results_v1{keys = Keys,
                                       terms = Terms,
                                       continuation = Continuation}} ->
                    {ok, Keys, Terms, Continuation};
                {error, _} = Error ->
                    Error
            end,
            {reply, Response, State};
        {get_index_range, Index, KeyStart, KeyEnd, Options0} ->
            Options1 = [{timeout, Timeout},
                        {call_timeout, Timeout + 100} | Options0],
            Response = case riakc_pb_socket:get_index_range(Connection,
                                                            Bucket, Index,
                                                            KeyStart, KeyEnd,
                                                            Options1) of
                {ok, #index_results_v1{keys = Keys,
                                       terms = Terms,
                                       continuation = Continuation}} ->
                    {ok, Keys, Terms, Continuation};
                {error, _} = Error ->
                    Error
            end,
            {reply, Response, State};
        {put, Key, ValueOrObject, Options0}
            when is_binary(Key), is_list(Options0) ->
            Defaults = [
                {content_type, undefined},
                {object, false},
                {indexes, []}],
            [ContentType, ObjectReply, Indexes | OptionsN] =
                cloudi_proplists:take_values(Defaults, Options0),
            Response = case ensure_object(Connection, Bucket, Key,
                                          ValueOrObject, Timeout) of
                {ok, Object0} ->
                    Object1 = object_update(Object0,
                                            ValueOrObject, ContentType),
                    Object2 = object_indexes(Object1, Indexes),
                    case riakc_pb_socket:put(Connection, Object2,
                                             OptionsN, Timeout) of
                        ok ->
                            if
                                ObjectReply =:= true ->
                                    {ok, Key, Object2};
                                ObjectReply =:= false ->
                                    object_to_tuple(Object2)
                            end;
                        {ok, ObjectN} ->
                            if
                                ObjectReply =:= true ->
                                    {ok, riakc_obj:key(ObjectN), ObjectN};
                                ObjectReply =:= false ->
                                    object_to_tuple(ObjectN)
                            end;
                        {error, _} = Error ->
                            Error
                    end;
                {error, _} = Error ->
                    Error
            end,
            {reply, Response, State}
    end.

cloudi_service_handle_info({ping, Ping} = Request,
                           #state{connection = Connection} = State,
                           Dispatcher) ->
    try riakc_pb_socket:ping(Connection) of
        pong ->
            erlang:send_after(Ping, cloudi_service:self(Dispatcher), Request),
            {noreply, State}
    catch
        _:Error ->
            {stop, {ping_failed, Error}, State}
    end;
cloudi_service_handle_info(Request, State, _) ->
    ?LOG_WARN("Unknown info \"~p\"", [Request]),
    {noreply, State}.

cloudi_service_terminate(_, undefined) ->
    ok;
cloudi_service_terminate(_, #state{connection = Connection}) ->
    (catch riakc_pb_socket:stop(Connection)),
    ok.

%%%------------------------------------------------------------------------
%%% Private functions
%%%------------------------------------------------------------------------

object_to_tuple(Object) ->
    case riakc_obj:get_values(Object) of
        [] ->
            {error, no_value};
        [Value] ->
            {ok, riakc_obj:key(Object), Value};
        Values ->
            {siblings, riakc_obj:key(Object), Values}
    end.

ensure_object(_, Bucket, _, ValueOrObject, _)
    when is_tuple(ValueOrObject) ->
    case riakc_obj:bucket(ValueOrObject) of
        Bucket ->
            {ok, ValueOrObject};
        _ ->
            {error, bucket_mismatch}
    end;
ensure_object(Connection, Bucket, Key, ValueOrObject, Timeout)
    when is_binary(ValueOrObject) ->
    riakc_pb_socket:get(Connection, Bucket, Key, [], Timeout).

object_update(Object, ValueOrObject, ContentType)
    when is_binary(ValueOrObject),
         is_list(ContentType), is_integer(hd(ContentType)) ->
    riakc_obj:update_value(Object, ValueOrObject, ContentType);
object_update(Object, ValueOrObject, undefined)
    when is_binary(ValueOrObject) ->
    riakc_obj:update_value(Object, ValueOrObject);
object_update(Object, ValueOrObject, ContentType)
    when is_tuple(ValueOrObject),
         is_list(ContentType), is_integer(hd(ContentType)) ->
    riakc_obj:update_content_type(Object, ContentType);
object_update(Object, ValueOrObject, undefined)
    when is_tuple(ValueOrObject) ->
    Object.

object_indexes(Object0, []) ->
    Object0;
object_indexes(Object0, [_ | _] = Indexes) ->
    MD0 = riakc_obj:get_update_metadata(Object0),
    MD1 = riakc_obj:clear_secondary_indexes(MD0),
    MD2 = riakc_obj:set_secondary_index(MD1, Indexes),
    riakc_obj:update_metadata(Object0, MD2).

