%%%-------------------------------------------------------------------
%%% @doc Mini Key-Value Store (Raw Erlang Actor Model)
%%% Demonstrates:
%%%   1. Process spawning and registration
%%%   2. Tail-recursive state loop with an immutable Map
%%%   3. Synchronous client/server message passing (Get, Keys, Size)
%%%   4. Asynchronous message passing (Put, Delete, Clear)
%%%   5. TTL expiration using erlang:send_after/3
%%% @end
%%%-------------------------------------------------------------------
-module(mini_kv).

%% Client API
-export([
    start/0,
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

%% Internal Process Callback
-export([loop/1]).

-define(SERVER, ?MODULE).

%%%===================================================================
%%% Client API
%%%===================================================================

%% Starts the KV store process and registers it under the module name
start() ->
    case whereis(?SERVER) of
        undefined ->
            InitialState = #{
                data => #{},       % #{Key => {Value, ExpireRef}}
                reads => 0,
                writes => 0,
                deletes => 0
            },
            Pid = spawn(?MODULE, loop, [InitialState]),
            register(?SERVER, Pid),
            {ok, Pid};
        Pid ->
            {error, {already_started, Pid}}
    end.

%% Stops the KV store process
stop() ->
    call({stop, self()}).

%% Stores a Key-Value pair indefinitely
put(Key, Value) ->
    cast({put, Key, Value, infinity}).

%% Stores a Key-Value pair with a Time-To-Live (in milliseconds)
put(Key, Value, TtlMs) when is_integer(TtlMs), TtlMs > 0 ->
    cast({put, Key, Value, TtlMs}).

%% Retrieves a Value by Key. Returns {ok, Value} or not_found
get(Key) ->
    call({get, self(), Key}).

%% Removes a Key
delete(Key) ->
    cast({delete, Key}).

%% Returns a list of all active keys
keys() ->
    call({keys, self()}).

%% Returns the number of items stored
size() ->
    call({size, self()}).

%% Clears all items
clear() ->
    cast(clear).

%% Returns store statistics (total reads, writes, deletes, item count)
stats() ->
    call({stats, self()}).

%%%===================================================================
%%% Helper Call / Cast wrappers
%%%===================================================================

%% Synchronous call: sends request with self() and waits for reply
call(Message) ->
    case whereis(?SERVER) of
        undefined ->
            {error, not_running};
        _Pid ->
            ?SERVER ! Message,
            receive
                {reply, Reply} -> Reply
            after 3000 ->
                {error, timeout}
            end
    end.

%% Asynchronous cast: fire-and-forget message
cast(Message) ->
    case whereis(?SERVER) of
        undefined ->
            {error, not_running};
        _Pid ->
            ?SERVER ! Message,
            ok
    end.

%%%===================================================================
%%% Server Loop (State preservation via recursion)
%%%===================================================================

loop(State) ->
    #{data := Data, reads := Reads, writes := Writes, deletes := Deletes} = State,

    receive
        %% Synchronous: Get
        {get, From, Key} ->
            Reply = case maps:find(Key, Data) of
                {ok, {Value, _TimerRef}} -> {ok, Value};
                error -> not_found
            end,
            From ! {reply, Reply},
            loop(State#{reads => Reads + 1});

        %% Synchronous: Keys
        {keys, From} ->
            AllKeys = maps:keys(Data),
            From ! {reply, AllKeys},
            loop(State);

        %% Synchronous: Size
        {size, From} ->
            From ! {reply, maps:size(Data)},
            loop(State);

        %% Synchronous: Stats
        {stats, From} ->
            StoreStats = #{
                items => maps:size(Data),
                total_reads => Reads,
                total_writes => Writes,
                total_deletes => Deletes
            },
            From ! {reply, StoreStats},
            loop(State);

        %% Synchronous: Stop
        {stop, From} ->
            %% Cancel any active timers before exiting
            cancel_all_timers(Data),
            From ! {reply, ok},
            ok;

        %% Asynchronous: Put (with optional TTL)
        {put, Key, Value, Ttl} ->
            %% If key already has an active timer, cancel it
            NewData1 = cancel_existing_timer(Key, Data),
            TimerRef = case Ttl of
                infinity ->
                    undefined;
                Ms ->
                    erlang:send_after(Ms, self(), {expire, Key})
            end,
            NewData2 = maps:put(Key, {Value, TimerRef}, NewData1),
            loop(State#{data => NewData2, writes => Writes + 1});

        %% Asynchronous: Delete
        {delete, Key} ->
            NewData = cancel_existing_timer(Key, Data),
            loop(State#{data => maps:remove(Key, NewData), deletes => Deletes + 1});

        %% Asynchronous: Clear
        {clear} ->
            cancel_all_timers(Data),
            loop(State#{data => #{}});

        %% Internal Timer: Expiration event triggered by erlang:send_after
        {expire, Key} ->
            %% Remove key when timer fires
            NewData = maps:remove(Key, Data),
            loop(State#{data => NewData});

        %% Catch-all for unexpected messages
        _Other ->
            loop(State)
    end.

%%%===================================================================
%%% Internal Utilities
%%%===================================================================

cancel_existing_timer(Key, Data) ->
    case maps:find(Key, Data) of
        {ok, {_Val, TimerRef}} when is_reference(TimerRef) ->
            erlang:cancel_timer(TimerRef),
            Data;
        _ ->
            Data
    end.

cancel_all_timers(Data) ->
    maps:foreach(
        fun(_Key, {_Val, TimerRef}) ->
            if is_reference(TimerRef) -> erlang:cancel_timer(TimerRef);
               true -> ok
            end
        end,
        Data
    ).
