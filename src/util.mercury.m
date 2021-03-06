%-----------------------------------------------------------------------%
% Mercury Utility code
% vim: ts=4 sw=4 et
%
% Copyright (C) 2015-2020 Plasma Team
% Distributed under the terms of the MIT License see ../LICENSE.code
%
%-----------------------------------------------------------------------%
:- module util.mercury.

:- interface.

:- import_module bag.
:- import_module cord.
:- import_module io.
:- import_module list.
:- import_module maybe.
:- import_module set.

%-----------------------------------------------------------------------%

    % Print the error to stderror and set the exit code to 1.
    %
    % Does not terminate the program.
    %
:- pred exit_error(string::in, io::di, io::uo) is det.

    % one_item([X]) = X.
    %
:- func one_item(list(T)) = T.

:- func maybe_list(maybe(X)) = list(X).

:- func maybe_cord(maybe(X)) = cord(X).

    % Mercury does not provide a map over maybe_error.
    %
:- func maybe_error_map(func(A) = B, maybe_error(A, E)) = maybe_error(B, E).

    % set_map_foldl2(Pred, Set0, Set, !Acc1, !Acc2),
    %
:- pred set_map_foldl2(pred(X, Y, A, A, B, B),
    set(X), set(Y), A, A, B, B).
:- mode set_map_foldl2(pred(in, out, in, out, in, out) is det,
    in, out, in, out, in, out) is det.

:- pred map2_corresponding(pred(X, Y, A, B), list(X), list(Y), list(A),
    list(B)).
:- mode map2_corresponding(pred(in, in, out, out) is det, in, in, out, out)
    is det.

:- pred map4_corresponding2(pred(A, B, C, D, X, Y), list(A), list(B),
    list(C), list(D), list(X), list(Y)).
:- mode map4_corresponding2(pred(in, in, in, in, out, out) is det, in, in,
    in, in, out, out) is det.

:- pred foldl4_corresponding(pred(X, Y, A, A, B, B, C, C, D, D),
    list(X), list(Y), A, A, B, B, C, C, D, D).
:- mode foldl4_corresponding(
    pred(in, in, in, out, in, out, in, out, in, out) is det,
    in, in, in, out, in, out, in, out, in, out) is det.

:- pred remove_first_match_map(pred(X, Y), Y, list(X), list(X)).
:- mode remove_first_match_map(pred(in, out) is semidet, out, in, out)
    is semidet.

    % det_uint32_to_int
    %
    % For some reason Mercury 20.01 doesn't provide this (it would be
    % uint32.det_to_int).
    %
:- func det_uint32_to_int(uint32) = int.

:- func det_uint64_to_int(uint64) = int.

%-----------------------------------------------------------------------%

:- func list_join(list(T), list(T)) = list(T).

:- func bag_list_to_bag(list(bag(T))) = bag(T).

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%
:- implementation.

:- import_module require.
:- import_module string.
:- import_module uint32.
:- import_module uint64.

%-----------------------------------------------------------------------%

exit_error(ErrMsg, !IO) :-
    write_string(stderr_stream, ErrMsg ++ "\n", !IO),
    set_exit_status(1, !IO).

%-----------------------------------------------------------------------%

one_item(Xs) =
    ( if Xs = [X] then
        X
    else
        unexpected($file, $pred, "Expected a list with only one item")
    ).

%-----------------------------------------------------------------------%

maybe_list(yes(X)) = [X].
maybe_list(no) = [].

%-----------------------------------------------------------------------%

maybe_cord(yes(X)) = singleton(X).
maybe_cord(no) = init.

%-----------------------------------------------------------------------%

maybe_error_map(_, error(Error)) = error(Error).
maybe_error_map(Func, ok(X)) = ok(Func(X)).

%-----------------------------------------------------------------------%

set_map_foldl2(Pred, Set0, Set, !Acc1, !Acc2) :-
    List0 = to_sorted_list(Set0),
    list.map_foldl2(Pred, List0, List, !Acc1, !Acc2),
    Set = list_to_set(List).

%-----------------------------------------------------------------------%

map2_corresponding(P, Xs0, Ys0, As, Bs) :-
    ( if
        Xs0 = [],
        Ys0 = []
    then
        As = [],
        Bs = []
    else if
        Xs0 = [X | Xs],
        Ys0 = [Y | Ys]
    then
        P(X, Y, A, B),
        map2_corresponding(P, Xs, Ys, As0, Bs0),
        As = [A | As0],
        Bs = [B | Bs0]
    else
        unexpected($file, $pred, "Mismatched inputs")
    ).

map4_corresponding2(P, As0, Bs0, Cs0, Ds0, Xs, Ys) :-
    ( if
        As0 = [],
        Bs0 = [],
        Cs0 = [],
        Ds0 = []
    then
        Xs = [],
        Ys = []
    else if
        As0 = [A | As],
        Bs0 = [B | Bs],
        Cs0 = [C | Cs],
        Ds0 = [D | Ds]
    then
        P(A, B, C, D, X, Y),
        map4_corresponding2(P, As, Bs, Cs, Ds, Xs0, Ys0),
        Xs = [X | Xs0],
        Ys = [Y | Ys0]
    else
        unexpected($file, $pred, "Mismatched inputs")
    ).

foldl4_corresponding(P, Xs0, Ys0, !A, !B, !C, !D) :-
    ( if
        Xs0 = [],
        Ys0 = []
    then
        true
    else if
        Xs0 = [X | Xs],
        Ys0 = [Y | Ys]
    then
        P(X, Y, !A, !B, !C, !D),
        foldl4_corresponding(P, Xs, Ys, !A, !B, !C, !D)
    else
        unexpected($file, $pred, "Input lists of different lengths")
    ).

%-----------------------------------------------------------------------%

remove_first_match_map(Pred, Y, [X | Xs], Ys) :-
    ( if Pred(X, YP) then
        Y = YP,
        Ys = Xs
    else
        remove_first_match_map(Pred, Y, Xs, Ys0),
        Ys = [X | Ys0]
    ).

%-----------------------------------------------------------------------%

det_uint32_to_int(Uint32) = Int :-
    Int = cast_to_int(Uint32),
    % This should catch cases when this doesn't work.
    ( if from_int(Int, Uint32) then
        true
    else
        unexpected($file, $pred, "Uint32 out of range")
    ).

%-----------------------------------------------------------------------%

det_uint64_to_int(Uint64) = Int :-
    Int = cast_to_int(Uint64),
    ( if from_int(Int, Uint64) then
        true
    else
        unexpected($file, $pred, "Uint64 out of range")
    ).

%-----------------------------------------------------------------------%

list_join(_, []) = [].
list_join(_, [X]) = [X].
list_join(J, [X1, X2 | Xs]) =
    [X1 | J ++ list_join(J, [X2 | Xs])].

%-----------------------------------------------------------------------%

bag_list_to_bag(LoB) =
    foldl(union, LoB, init).

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%
