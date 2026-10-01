%%%-------------------------------------------------------------------
%%% @doc Demo & Test Runner for Mini KV Store
%%% Runs a complete suite of tests on both mini_kv and mini_kv_otp
%%% @end
%%%-------------------------------------------------------------------
-module(demo).
-export([run/0]).

run() ->
    io:format("~n======================================================~n"),
    io:format("      TESTING RAW ACTOR KV STORE (mini_kv)            ~n"),
    io:format("======================================================~n"),
    test_module(mini_kv, fun() -> mini_kv:start() end, fun() -> mini_kv:stop() end),

    io:format("~n======================================================~n"),
    io:format("      TESTING OTP GEN_SERVER KV STORE (mini_kv_otp)   ~n"),
    io:format("======================================================~n"),
    test_module(mini_kv_otp, fun() -> mini_kv_otp:start_link() end, fun() -> mini_kv_otp:stop() end),

    io:format("~n [SUCCESS] All tests passed cleanly!~n~n"),
    init:stop().

test_module(Mod, StartFun, StopFun) ->
    %% 1. Start
    io:format("1. Starting ~p...~n", [Mod]),
    {ok, _Pid} = StartFun(),

    %% 2. Basic Put / Get
    io:format("2. Testing Put and Get...~n"),
    ok = Mod:put(user_1, "Alice"),
    ok = Mod:put(user_2, "Bob"),
    ok = Mod:put(config, #{theme => dark, port => 8080}),

    {ok, "Alice"} = Mod:get(user_1),
    {ok, "Bob"} = Mod:get(user_2),
    {ok, #{theme := dark}} = Mod:get(config),
    not_found = Mod:get(non_existing_key),
    io:format("   -> Got expected values for user_1, user_2, config.~n"),

    %% 3. Keys and Size
    io:format("3. Testing Keys and Size...~n"),
    3 = Mod:size(),
    AllKeys = Mod:keys(),
    io:format("   -> Stored ~p items. Keys: ~p~n", [Mod:size(), AllKeys]),

    %% 4. Delete
    io:format("4. Testing Delete...~n"),
    ok = Mod:delete(user_2),
    not_found = Mod:get(user_2),
    2 = Mod:size(),
    io:format("   -> user_2 deleted successfully. New size: ~p~n", [Mod:size()]),

    %% 5. TTL Expiration (Key expires in 500 ms)
    io:format("5. Testing TTL auto-expiration (500ms)...~n"),
    ok = Mod:put(temp_token, "xyz-secret-123", 500),
    {ok, "xyz-secret-123"} = Mod:get(temp_token),
    io:format("   -> temp_token is present immediately after put.~n"),
    io:format("   -> Sleeping for 650ms to let timer fire...~n"),
    timer:sleep(650),
    not_found = Mod:get(temp_token),
    io:format("   -> temp_token successfully expired and was garbage collected!~n"),

    %% 6. Stats
    io:format("6. Checking stats...~n"),
    Stats = Mod:stats(),
    io:format("   -> Stats: ~p~n", [Stats]),

    %% 7. Stop
    io:format("7. Stopping ~p...~n", [Mod]),
    ok = StopFun(),
    io:format("   -> Stopped successfully.~n").
