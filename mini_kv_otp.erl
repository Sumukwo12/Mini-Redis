%%%-------------------------------------------------------------------
%%% @doc Mini Key-Value Store (OTP gen_server version)
%%% Demonstrates:
%%%   1. Standard Erlang/OTP gen_server behavior
%%%   2. Synchronous handle_call (Get, Keys, Size, Stats)
%%%   3. Asynchronous handle_cast (Put, Delete, Clear)
%%%   4. Internal timer messages with handle_info (TTL Expiration)
%%% @end
%%%-------------------------------------------------------------------
-module(mini_kv_otp).
-behaviour(gen_server).

%% Client API
-export([
    start_link/0,
    stop/0,
    put/2,
    put/3,
    get/1,
    delete/1,
    keys/0,
    size/0,
    clear/0,
    stats/0
]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3
]).

-define(SERVER, ?MODULE).

-record(state, {
    data = #{} :: map(),     % #{Key => {Value, TimerRef | undefined}}
    reads = 0 :: non_neg_integer(),
    writes = 0 :: non_neg_integer(),
    deletes = 0 :: non_neg_integer()
}).

%%%===================================================================
%%% Client API
%%%===================================================================

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:stop(?SERVER).

put(Key, Value) ->
    gen_server:cast(?SERVER, {put, Key, Value, infinity}).

put(Key, Value, TtlMs) when is_integer(TtlMs), TtlMs > 0 ->
    gen_server:cast(?SERVER, {put, Key, Value, TtlMs}).

get(Key) ->
    gen_server:call(?SERVER, {get, Key}).

delete(Key) ->
    gen_server:cast(?SERVER, {delete, Key}).

keys() ->
    gen_server:call(?SERVER, keys).

size() ->
    gen_server:call(?SERVER, size).

clear() ->
    gen_server:cast(?SERVER, clear).

stats() ->
    gen_server:call(?SERVER, stats).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init([]) ->
    {ok, #state{}}.

handle_call({get, Key}, _From, State = #state{data = Data, reads = Reads}) ->
    Reply = case maps:find(Key, Data) of
        {ok, {Value, _TimerRef}} -> {ok, Value};
        error -> not_found
    end,
    {reply, Reply, State#state{reads = Reads + 1}};

handle_call(keys, _From, State = #state{data = Data}) ->
    {reply, maps:keys(Data), State};

handle_call(size, _From, State = #state{data = Data}) ->
    {reply, maps:size(Data), State};

handle_call(stats, _From, State = #state{data = Data, reads = R, writes = W, deletes = D}) ->
    Stats = #{
        items => maps:size(Data),
        total_reads => R,
        total_writes => W,
        total_deletes => D
    },
    {reply, Stats, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({put, Key, Value, Ttl}, State = #state{data = Data, writes = Writes}) ->
    Data1 = cancel_timer(Key, Data),
    TimerRef = case Ttl of
        infinity -> undefined;
        Ms -> erlang:send_after(Ms, self(), {expire, Key})
    end,
    Data2 = maps:put(Key, {Value, TimerRef}, Data1),
    {noreply, State#state{data = Data2, writes = Writes + 1}};

handle_cast({delete, Key}, State = #state{data = Data, deletes = Deletes}) ->
    Data1 = cancel_timer(Key, Data),
    {noreply, State#state{data = maps:remove(Key, Data1), deletes = Deletes + 1}};

handle_cast(clear, State = #state{data = Data}) ->
    cancel_all(Data),
    {noreply, State#state{data = #{}}};

handle_cast(_Msg, State) ->
    {noreply, State}.

%% Expiration message received from erlang:send_after
handle_info({expire, Key}, State = #state{data = Data}) ->
    {noreply, State#state{data = maps:remove(Key, Data)}};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{data = Data}) ->
    cancel_all(Data),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

cancel_timer(Key, Data) ->
    case maps:find(Key, Data) of
        {ok, {_Val, TimerRef}} when is_reference(TimerRef) ->
            erlang:cancel_timer(TimerRef),
            Data;
        _ ->
            Data
    end.

cancel_all(Data) ->
    maps:foreach(
        fun(_Key, {_Val, TimerRef}) ->
            if is_reference(TimerRef) -> erlang:cancel_timer(TimerRef);
               true -> ok
            end
        end,
        Data
    ).
