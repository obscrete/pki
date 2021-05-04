-module(test_keydir_service).
-export([start/0, start/1]).
-export([password_login/1, bank_id_login/1]).

-include("../include/keydir_service.hrl").

-define(PASSWORD, <<"mortuta42">>).
-define(VALID_PERSONAL_NUMBER, <<"201701012393">>).

start() ->
    start(password).

start(LoginMode) ->
    AliceKeyId = <<"alice">>,
    EncodedAliceKeyId = base64:encode(AliceKeyId),
    AliceKey =
        case LoginMode of
            password ->
                base64:encode(
                  jsone:encode(
                    #{<<"keyId">> => EncodedAliceKeyId,
                      <<"fingerprint">> => EncodedAliceKeyId,
                      <<"userIds">> => [<<"alice">>],
                      <<"userAttributes">> => []}));
            bank_id ->
                base64:encode(
                  jsone:encode(
                    #{<<"keyId">> => EncodedAliceKeyId,
                      <<"fingerprint">> => EncodedAliceKeyId,
                      <<"userIds">> => [<<"alice">>],
                      <<"userAttributes">> => [#{<<"type">> => ?PERSONAL_NUMBER_ATTRIBUTE,
                                                 <<"value">> => ?VALID_PERSONAL_NUMBER}]}))
        end,

    BobKeyId = <<"bob">>,
    EncodedBobKeyId = base64:encode(BobKeyId),
    BobKey =
        base64:encode(
          jsone:encode(
            #{<<"keyId">> => EncodedBobKeyId,
              <<"fingerprint">> => EncodedBobKeyId,
              <<"userIds">> => [],
              <<"userAttributes">> =>
                  [#{<<"type">> => ?NYM_ATTRIBUTE,
                     <<"value">> => <<"bob">>}]})),

    ChuckKeyId = <<"chuck">>,
    EncodedChuckKeyId = base64:encode(ChuckKeyId),
    ChuckKey =
        base64:encode(
          jsone:encode(
            #{<<"keyId">> => EncodedChuckKeyId,
              <<"fingerprint">> => EncodedChuckKeyId,
              <<"userIds">> => [<<"alice">>, <<"bob">>],
              <<"userAttributes">> =>
                  [#{<<"type">> => ?NYM_ATTRIBUTE,
                     <<"value">> => <<"alice">>}]})),

    FredKeyId = <<"fred">>,
    EncodedFredKeyId = base64:encode(FredKeyId),
    FredKey =
        base64:encode(
          jsone:encode(
            #{<<"keyId">> => EncodedFredKeyId,
              <<"fingerprint">> => EncodedFredKeyId,
              <<"userIds">> => [],
              <<"userAttributes">> =>
                  [#{<<"type">> => ?NYM_ATTRIBUTE,
                     <<"value">> => <<"fred">>}]})),

    %%
    io:format("**** Read a non-exsting key (should fail)\n"),
    {ok, 404, #{<<"errorMessage">> := <<"No such key">>}} =
        json_post(
          "https://127.0.0.1:4436/read",
          #{<<"keyId">> => EncodedAliceKeyId}),
    
    %%
    io:format("**** Login as Bob\n"),
    {ok, BobSessionTicket} = password_login(EncodedBobKeyId),
    
    %%
    io:format("**** Try to create a key with a mismatched Key ID\n"),
    {ok, 401, #{<<"errorMessage">> :=
                    <<"Key ID does not match login credentials">>}} =
        json_post("https://127.0.0.1:4436/create",
                  #{<<"sessionTicket">> => BobSessionTicket,
                    <<"key">> => AliceKey}),

    %%
    io:format("**** Create Bob's key\n"),
    {ok, 200} =
        json_post("https://127.0.0.1:4436/create",
                  #{<<"sessionTicket">> => BobSessionTicket,
                    <<"key">> => BobKey}),
    
    %%
    io:format("**** Login as Chuck\n"),
    {ok, ChuckSessionTicket} = password_login(EncodedChuckKeyId),
    
    %%
    io:format("**** Create Chuck's key\n"),
    {ok, 200} =
        json_post("https://127.0.0.1:4436/create",
                  #{<<"sessionTicket">> => ChuckSessionTicket,
                    <<"key">> => ChuckKey}),

    %%
    io:format("**** Logout Bob\n"),
    {ok, 200} =
        json_post("https://127.0.0.1:4436/logout",
                  #{<<"sessionTicket">> => BobSessionTicket}),

    %%
    io:format("**** Logout Bob again (should fail)\n"),
    {ok, 403, #{<<"errorMessage">> := <<"No such session">>}} =
        json_post("https://127.0.0.1:4436/logout",
                  #{<<"sessionTicket">> => BobSessionTicket}),

    %%
    io:format("**** Login as Alice\n"),
    {ok, AliceSessionTicket} =
        case LoginMode of
            password ->
                password_login(EncodedAliceKeyId);
            bank_id ->
                bank_id_login(EncodedAliceKeyId)
        end,

    %%
    io:format("**** Create Alice'a key with Bob's stale session ticket\n"),
    {ok, 403, #{<<"errorMessage">> := <<"No active session">>}} =
        json_post("https://127.0.0.1:4436/create",
                  #{<<"sessionTicket">> => BobSessionTicket,
                    <<"key">> => AliceKey}),
    
    %%
    io:format("**** Create Alice's key\n"),
    {ok, 200} =
        json_post("https://127.0.0.1:4436/create",
                  #{<<"sessionTicket">> => AliceSessionTicket,
                    <<"key">> => AliceKey}),

    %%
    io:format("**** Create Alice's key again (should fail)\n"),
    {ok, 303, #{<<"errorMessage">> := <<"Key already exists">>}} =
        json_post("https://127.0.0.1:4436/create",
                  #{<<"sessionTicket">> => AliceSessionTicket,
                    <<"key">> => AliceKey}),

    %%
    io:format("**** Read Alice's key\n"),
    {ok, 200, AliceKey} =
        json_post(
          "https://127.0.0.1:4436/read",
          #{<<"keyId">> => EncodedAliceKeyId,
            <<"verified">> => (LoginMode == bank_id)}),
    
    %%
    io:format("**** Read Alice's key with the help of Alice's User ID (Chuck's key will returned as well!)\n"),
    {ok, 200, #{<<"keys">> := MatchingUserIdAliceKeys}} =
        json_post(
          "https://127.0.0.1:4436/read",
          #{<<"userId">> => <<"alice">>}),
    case LoginMode of
        password ->
            [#{<<"fingerprint">> := EncodedChuckKeyId,
               <<"keyId">> := EncodedChuckKeyId,
               <<"nym">> := <<"alice">>,
               <<"userIds">> := [<<"alice">>,<<"bob">>],
               <<"verified">> := false},
             #{<<"fingerprint">> := EncodedAliceKeyId,
               <<"keyId">> := EncodedAliceKeyId,
               <<"nym">> := <<"alice">>,
               <<"userIds">> := [<<"alice">>],
               <<"verified">> := false}] =
                lists:sort(MatchingUserIdAliceKeys);
        bank_id ->
            [#{<<"keyId">> := EncodedChuckKeyId,
               <<"fingerprint">> := EncodedChuckKeyId,
               <<"nym">> := <<"alice">>,
               <<"userIds">> := [<<"alice">>,<<"bob">>],
               <<"verified">> := false},
             #{<<"keyId">> := EncodedAliceKeyId,
               <<"fingerprint">> := EncodedAliceKeyId,
               <<"nym">> := <<"alice">>,
               <<"personalNumber">> := <<"201701012393">>,
               <<"userIds">> := [<<"alice">>],
               <<"verified">> := true}] =
                lists:sort(MatchingUserIdAliceKeys)
    end,

    %%
    io:format("**** Read Alice's key with the help of Alice's User ID *and* Key ID\n"),
    {ok, 200, AliceKey} =
        json_post(
          "https://127.0.0.1:4436/read",
          #{<<"keyId">> => EncodedAliceKeyId,
            <<"userId">> => <<"alice">>}),
    
    %%
    io:format("**** Read Alice's key with the help of Alice's Nym (Chuck's key will returned as well!)\n"),
    {ok, 200, #{<<"keys">> := MatchingNymAliceKeys}} =
        json_post(
          "https://127.0.0.1:4436/read",
          #{<<"nym">> => <<"alice">>}),
    case LoginMode of
        password ->
            [#{<<"fingerprint">> := EncodedChuckKeyId,
               <<"keyId">> := EncodedChuckKeyId,
               <<"nym">> := <<"alice">>,
               <<"userIds">> := [<<"alice">>,<<"bob">>],
               <<"verified">> := false},
             #{<<"fingerprint">> := EncodedAliceKeyId,
               <<"keyId">> := EncodedAliceKeyId,
               <<"nym">> := <<"alice">>,
               <<"userIds">> := [<<"alice">>],
               <<"verified">> := false}] =
                lists:sort(MatchingNymAliceKeys);
        bank_id ->
            [#{<<"keyId">> := EncodedChuckKeyId,
               <<"fingerprint">> := EncodedChuckKeyId,
               <<"nym">> := <<"alice">>,
               <<"userIds">> := [<<"alice">>,<<"bob">>],
               <<"verified">> := false},
             #{<<"keyId">> := EncodedAliceKeyId,
               <<"fingerprint">> := EncodedAliceKeyId,
               <<"nym">> := <<"alice">>,
               <<"personalNumber">> := <<"201701012393">>,
               <<"userIds">> := [<<"alice">>],
               <<"verified">> := true}] =
                lists:sort(MatchingNymAliceKeys)
    end,

    %%
    io:format("**** Read a non-exsting key using HKP lookup (should fail)\n"),
    {ok, 404, #{<<"errorMessage">> := <<"No such key">>}} =
        http_get("https://127.0.0.1:4436/pks/lookup?op=get&search=0xfeedbabeff"),

    io:format("**** Read Alice's key using HKP\n"),
    {ok, 200, AliceKey} =
        http_get("https://127.0.0.1:4436/pks/lookup?op=get&search=0x" ++
                     keydir_service:bin_to_hexstr(AliceKeyId)),

    %%
    io:format("**** Create Fred's key using HKP\n"),
    {ok, 200} = http_post("https://127.0.0.1:4436/pks/add", FredKey),

    %%
    io:format("**** Create Fred's key again with HKP (should fail)\n"),
    {ok, 303, #{<<"errorMessage">> := <<"Key already exists">>}} =
        http_post("https://127.0.0.1:4436/pks/add", FredKey),
    
    %%
    io:format("**** Delete Alice's key using Chuck's session ticket (should fail)\n"),
    {ok, 403, #{<<"errorMessage">> := <<"Session mismatch">>}} =
        json_post(
          "https://127.0.0.1:4436/delete",
          #{<<"sessionTicket">> => ChuckSessionTicket,
            <<"keyId">> => EncodedAliceKeyId}),
    
    %%
    io:format("**** Logout Chuck\n"),
    {ok, 200} =
        json_post("https://127.0.0.1:4436/logout",
                  #{<<"sessionTicket">> => ChuckSessionTicket}).

password_login(EncodedKeyId) ->
    {ok, 200, #{<<"sessionTicket">> := SessionTicket}} =
        json_post("https://127.0.0.1:4436/passwordLogin",
                  #{<<"keyId">> => EncodedKeyId,
                    <<"password">> => ?PASSWORD}),
    {ok, SessionTicket}.

bank_id_login(EncodedKeyId) ->
    bank_id_auth(EncodedKeyId).

bank_id_auth(EncodedKeyId) ->
    {ok, 200, #{<<"sessionTicket">> := SessionTicket}} =
        json_post("https://127.0.0.1:4436/bankIdAuth",
                  #{<<"keyId">> => EncodedKeyId,
                    <<"personalNumber">> => ?VALID_PERSONAL_NUMBER}),
    bank_id_collect(SessionTicket).

bank_id_collect(SessionTicket) ->
    case json_post("https://127.0.0.1:4436/bankIdCollect",
                   #{<<"sessionTicket">> => SessionTicket}) of
        {ok, 200, #{<<"status">> := <<"pending">>,
                    <<"hintCode">> := HintCode}} ->
            io:format("** COLLECT: pending (~p)\n", [HintCode]),
            timer:sleep(2000),
            bank_id_collect(SessionTicket);
        {ok, 200, #{<<"status">> := <<"failed">>,
                    <<"hintCode">> := HintCode}} ->
            io:format("** COLLECT: failed (~p)\n", [HintCode]),
            {error, failed};
        {ok, 200, #{<<"status">> := <<"complete">>}} ->
            io:format("** COLLECT: complete\n"),
            {ok, SessionTicket}
    end.

%%
%% Helpers
%%

json_post(Url, JsonValue) ->
    RequestBody =
        jsone:encode(JsonValue,
                     [{float_format, [{decimals, 4}, compact]},
                      {indent, 2},
                      {object_key_type, value},
                      {space, 1},
                      native_forward_slash]),
    case httpc:request(
           post,
           {Url, [], "application/json", RequestBody},
           [{timeout, 120 * 1000}],
           [{body_format, binary}]) of
        {ok, {{_Version, StatusCode, _ReasonPhrase}, _Headers, <<>>}} ->
            {ok, StatusCode};
        {ok, {{_Version, StatusCode, _ReasonPhrase}, Headers, ResponseBody}} ->
            case lists:keysearch("content-type", 1, Headers) of
                {value, {_, "application/json"}} ->
                    {ok, StatusCode, jsone:decode(ResponseBody)};
                _ ->
                    {ok, StatusCode, ResponseBody}
            end;
        {error, Reason} ->
            {error, Reason}
    end.
    
http_get(Url) ->
    case httpc:request(get, {Url, []}, [{timeout, 120 * 1000}],
                       [{body_format, binary}]) of
        {ok, {{_Version, StatusCode, _ReasonPhrase}, _Headers, <<>>}} ->
            {ok, StatusCode};
        {ok, {{_Version, StatusCode, _ReasonPhrase}, Headers, ResponseBody}} ->
            case lists:keysearch("content-type", 1, Headers) of
                {value, {_, "application/json"}} ->
                    {ok, StatusCode, jsone:decode(ResponseBody)};
                _ ->
                    {ok, StatusCode, ResponseBody}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

http_post(Url, Body) ->
    case httpc:request(
           post,
           {Url, [], "application/octet-stream", Body},
           [{timeout, 120 * 1000}],
           [{body_format, binary}]) of
        {ok, {{_Version, StatusCode, _ReasonPhrase}, _Headers, <<>>}} ->
            {ok, StatusCode};
        {ok, {{_Version, StatusCode, _ReasonPhrase}, Headers, ResponseBody}} ->
            case lists:keysearch("content-type", 1, Headers) of
                {value, {_, "application/json"}} ->
                    {ok, StatusCode, jsone:decode(ResponseBody)};
                _ ->
                    {ok, StatusCode, ResponseBody}
            end;
        {error, Reason} ->
            {error, Reason}
    end.