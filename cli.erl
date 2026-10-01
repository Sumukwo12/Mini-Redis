%%%-------------------------------------------------------------------
%%% @doc Interactive CLI for Mini-Redis Key-Value Store
%%% Allows users to interactively type commands like:
%%%   SET name Alice
%%%   GET name
%%%   SETEX token 9876 5000
%%%   KEYS
%%%   STATS
%%%   DEL name
%%%   QUIT
%%% @end
%%%-------------------------------------------------------------------
-module(cli).
-export([start/0, run/0]).

start() ->
    run().

run() ->
    %% Ensure KV store is running
    mini_kv:start(),
    print_welcome(),
    loop().

print_welcome() ->
    io:format("~n======================================================~n"),
    io:format("        WELCOME TO MINI-REDIS INTERACTIVE CLI         ~n"),
    io:format("======================================================~n"),
    io:format("Available commands:~n"),
    io:format("  SET <key> <value>          - Store a value~n"),
    io:format("  SETEX <key> <value> <ms>   - Store with auto-expiration (TTL)~n"),
    io:format("  GET <key>                  - Read a value~n"),
    io:format("  DEL <key>                  - Delete a key~n"),
    io:format("  KEYS                       - List all active keys~n"),
    io:format("  SIZE                       - Count of stored items~n"),
    io:format("  STATS                      - View reads, writes, metrics~n"),
    io:format("  CLEAR                      - Delete everything~n"),
    io:format("  HELP                       - Show this menu~n"),
    io:format("  QUIT / EXIT                - Exit the program~n"),
    io:format("======================================================~n~n").

loop() ->
    case io:get_line("mini-redis> ") of
        eof ->
            io:format("~nGoodbye!~n"),
            init:stop();
        {error, Reason} ->
            io:format("Input error: ~p~n", [Reason]),
            init:stop();
        Line ->
            Trimmed = string:trim(Line),
            case parse_line(Trimmed) of
                quit ->
                    io:format("Exiting Mini-Redis. Goodbye!~n~n"),
                    mini_kv:stop(),
                    init:stop();
                empty ->
                    loop();
                {ok, Command} ->
                    handle_command(Command),
                    loop()
            end
    end.

parse_line("") ->
    empty;
parse_line(Line) ->
    %% Strip accidental pasted prompts like "mini-redis>" or ">"
    CleanLine = case Line of
        "mini-redis>" ++ Rest -> string:trim(Rest);
        ">" ++ Rest -> string:trim(Rest);
        _ -> Line
    end,
    Tokens = string:tokens(CleanLine, " \t"),
    case Tokens of
        [] -> empty;
        [Cmd | Args] ->
            LowerCmd = string:to_lower(Cmd),
            case LowerCmd of
                "quit" -> quit;
                "exit" -> quit;
                "q"    -> quit;
                _      -> {ok, {LowerCmd, Args}}
            end
    end.

handle_command({"help", _}) ->
    print_welcome();

handle_command({"set", [KeyStr | ValParts]}) when length(ValParts) > 0 ->
    Key = list_to_atom(KeyStr),
    Value = string:join(ValParts, " "),
    ok = mini_kv:put(Key, Value),
    io:format("OK: Stored ~p => ~p~n", [Key, Value]);
handle_command({"set", _}) ->
    io:format("ERROR: Syntax is: SET <key> <value>~n");

handle_command({"setex", [KeyStr, ValStr, TtlStr]}) ->
    Key = list_to_atom(KeyStr),
    case string:to_integer(TtlStr) of
        {error, _} ->
            io:format("ERROR: TTL must be a positive integer in milliseconds!~n");
        {TtlMs, []} when TtlMs > 0 ->
            ok = mini_kv:put(Key, ValStr, TtlMs),
            io:format("OK: Stored ~p => ~p (Expires in ~p ms)~n", [Key, ValStr, TtlMs]);
        _ ->
            io:format("ERROR: TTL must be greater than 0!~n")
    end;
handle_command({"setex", _}) ->
    io:format("ERROR: Syntax is: SETEX <key> <value> <milliseconds>~n");

handle_command({"get", [KeyStr]}) ->
    Key = list_to_atom(KeyStr),
    case mini_kv:get(Key) of
        {ok, Value} ->
            io:format("VALUE: ~p~n", [Value]);
        not_found ->
            io:format("(nil) - Key does not exist or has expired.~n")
    end;
handle_command({"get", _}) ->
    io:format("ERROR: Syntax is: GET <key>~n");

handle_command({"del", [KeyStr]}) ->
    Key = list_to_atom(KeyStr),
    ok = mini_kv:delete(Key),
    io:format("OK: Deleted key ~p~n", [Key]);
handle_command({"del", _}) ->
    io:format("ERROR: Syntax is: DEL <key>~n");

handle_command({"keys", _}) ->
    Keys = mini_kv:keys(),
    case Keys of
        [] ->
            io:format("(empty list or set)~n");
        _ ->
            io:format("Active Keys (~p):~n", [length(Keys)]),
            lists:foreach(fun(K) -> io:format("  * ~s~n", [atom_to_list(K)]) end, Keys)
    end;

handle_command({"size", _}) ->
    Count = mini_kv:size(),
    io:format("Current stored keys count: ~p~n", [Count]);

handle_command({"stats", _}) ->
    Stats = mini_kv:stats(),
    #{items := Items, total_reads := Reads, total_writes := Writes, total_deletes := Deletes} = Stats,
    io:format("--- Store Statistics ---~n"),
    io:format("  Active Items  : ~p~n", [Items]),
    io:format("  Total Reads   : ~p~n", [Reads]),
    io:format("  Total Writes  : ~p~n", [Writes]),
    io:format("  Total Deletes : ~p~n", [Deletes]);

handle_command({"clear", _}) ->
    ok = mini_kv:clear(),
    io:format("OK: Database cleared.~n");

handle_command({Unknown, _}) ->
    io:format("Unknown command: ~s. Type 'HELP' to see all commands.~n", [Unknown]).
