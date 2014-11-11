-module(chanman).
-export([start/1, start/2, start_link/1, start_link/2, code_change/2]).

%% Startup
start(Parent)            -> start(Parent, none).
start(Parent, Conf)      -> starter(fun spawn/1, Parent, Conf).
start_link(Parent)       -> start_link(Parent, none).
start_link(Parent, Conf) -> starter(fun spawn_link/1, Parent, Conf).

starter(Spawn, Parent, Conf) ->
    Name = ?MODULE,
    case whereis(Name) of
        undefined ->
            Pid = Spawn(fun() -> init(Parent, Conf) end),
            true = register(Name, Pid),
            {ok, Pid};
        Pid ->
            {ok, Pid}
    end.

init(Parent, Conf) ->
    note("Notional initialization with ~tp.", [Conf]),
    Channels = case Conf of
        none -> orddict:new();
        _    -> init_registry(Conf)
    end,
    loop(Parent, Channels).

init_registry(Conf) -> orddict:from_list(Conf).

%% Service
loop(Parent, Channels) ->
  receive
    {From, Ref, {join, {Con, Channel}}} ->
        ChanPid = join(Channel, Con, Channels),
        From ! {Ref, ChanPid},
        loop(Parent, Channels);
    status ->
        note("Channels ~p", [Channels]);
    code_change ->
        ?MODULE:code_change(Parent, Channels);
    shutdown ->
        note("Shutting down."),
        exit(shutdown);
    Any ->
        note("Received ~tp", [Any]),
        loop(Parent, Channels)
  end.

%% Magic
lookup(Name, Channels) ->
    case orddict:find(Name, Channels) of
        error   -> {error, absent};
        ChanPid -> {ok, ChanPid}
    end.

join(Channel, {Handle, ConPid}, Channels) ->
    case lookup(Channel, Channels) of
        {ok, ChanPid} ->
            ChanPid ! {add, {Handle, ConPid}},
            ChanPid;
        {error, absent} ->
            Owner = {Handle, {ConPid, owner}},
            ChanPid = channel:start_link(self(), Channel, {[Owner], []}),
            orddict:store(Channel, ChanPid, Channels),
            ChanPid
    end.

%% Code changer
code_change(Parent, Channels) ->
    note("Changing code."),
    loop(Parent, Channels).

%% System
note(String) ->
    note(String, []).

note(String, Args) ->
    em_lib:note(?MODULE, String, Args).
