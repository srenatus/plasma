%-----------------------------------------------------------------------%
% Plasma code pretty printer
% vim: ts=4 sw=4 et
%
% Copyright (C) 2016-2020 Plasma Team
% Distributed under the terms of the MIT License see ../LICENSE.code
%
%-----------------------------------------------------------------------%
:- module core.pretty.
%-----------------------------------------------------------------------%

:- interface.

:- import_module cord.
:- import_module string.

:- import_module util.
:- import_module util.pretty.

:- func core_pretty(core) = cord(string).

    % Pretty print a function declaration (used by write_interface).
    %
:- func func_decl_pretty(core, function) = list(pretty).

    % This is used by the code-generator's comments, so it returns a
    % string.
    %
:- func func_call_pretty(core, function, varmap, list(var)) = string.

:- func type_pretty(core, type_) = pretty.

    % Print the argument parts of a function type.  You can either put
    % "func" in front of this or the name of the variable at a call site.
    %
    % It is also used only by the code generator's commenting.
    %
:- func type_pretty_func(core, string, list(type_), list(type_),
    set(resource_id), set(resource_id)) = string.

    % func_pretty_template(Name, Inputs, Outputs, Uses, Observes) = Pretty.
    %
    % This function can print something in the style of a function
    % declaration.  Whether the arguments are names, types, or both.
    %
:- func func_pretty_template(pretty, list(pretty), list(pretty), list(pretty),
    list(pretty)) = pretty.

:- func resource_pretty(core, resource_id) = pretty.

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%

:- implementation.

:- import_module pair.
:- import_module require.

:- import_module builtins.
:- import_module context.
:- import_module util.mercury.
:- import_module varmap.

%-----------------------------------------------------------------------%

core_pretty(Core) = pretty(default_options, 0, Pretty) :-
    ModuleDecl = [p_str(format("module %s",
        [s(q_name_to_string(module_name(Core)))]))],
    Funcs = map(func_pretty(Core), core_all_functions(Core)),
    Pretty = [p_list(ModuleDecl ++ condense(Funcs)), p_nl_hard].

:- func func_pretty(core, func_id) = list(pretty).

func_pretty(Core, FuncId) = FuncPretty :-
    core_get_function_det(Core, FuncId, Func),
    FuncId = func_id(FuncIdInt),
    FuncIdPretty = [p_str(format("// func: %d", [i(FuncIdInt)])), p_nl_hard],
    FuncDecl = func_decl_pretty(Core, Func),
    ( if func_get_body(Func, _, _, _, _) then
        FuncPretty0 = [p_group_curly(FuncDecl, singleton("{"),
            func_body_pretty(Core, Func), singleton("}"))]
    else
        FuncPretty0 = [p_expr(FuncDecl ++ [p_str(";")])]
    ),
    FuncPretty = [p_nl_double] ++ FuncIdPretty ++ FuncPretty0.

func_decl_pretty(Core, Func) =
        [p_str("func "),
         func_pretty_template(Name, Args, Returns, Uses, Observes)] :-
    Name = p_str(q_name_to_string(func_get_name(Func))),
    func_get_type_signature(Func, ParamTypes, ReturnTypes, _),
    ( if func_get_body(Func, Varmap, ParamNames, _Captured, _Expr) then
        Args = params_pretty(Core, Varmap, ParamNames, ParamTypes)
    else
        Args = map(type_pretty(Core), ParamTypes)
    ),
    Returns = map(type_pretty(Core), ReturnTypes),

    func_get_resource_signature(Func, UsesSet, ObservesSet),
    Uses = map(resource_pretty(Core), set.to_sorted_list(UsesSet)),
    Observes = map(resource_pretty(Core), set.to_sorted_list(ObservesSet)).

func_call_pretty(Core, Func, Varmap, Args) =
    pretty_str([func_call_pretty_2(Core, Func, Varmap, Args)]).

:- func func_call_pretty_2(core, function, varmap, list(var)) = pretty.

func_call_pretty_2(Core, Func, Varmap, Args) =
        func_pretty_template(Name, ArgsPretty, [], [], []) :-
    Name = p_str(q_name_to_string(func_get_name(Func))),
    func_get_type_signature(Func, ParamTypes, _, _),
    ArgsPretty = params_pretty(Core, Varmap, Args, ParamTypes).

:- func params_pretty(core, varmap, list(var), list(type_)) =
    list(pretty).

params_pretty(Core, Varmap, Names, Types) =
    map_corresponding(param_pretty(Core, Varmap), Names, Types).

:- func param_pretty(core, varmap, var, type_) = pretty.

param_pretty(Core, Varmap, Var, Type) =
    p_expr([var_pretty(Varmap, Var), p_str(" : "),
        p_nl_soft, type_pretty(Core, Type)]).

:- func func_body_pretty(core, function) = list(pretty).

func_body_pretty(Core, Func) = Pretty :-
    ( if func_get_body(Func, VarmapPrime, _, CapturedPrime, ExprPrime) then
        Varmap = VarmapPrime,
        Captured = CapturedPrime,
        Expr = ExprPrime
    else
        unexpected($file, $pred, "Abstract function")
    ),

    expr_pretty(Core, Varmap, Expr, ExprPretty, 0, _, map.init, _InfoMap),

    ( Captured = [],
        CapturedPretty = []
    ; Captured = [_ | _],
        CapturedPretty = [p_nl_double,
            p_comment(singleton("// "),
                [p_str("Captured: "), p_nl_soft] ++
                pretty_seperated([p_str(", "), p_nl_soft],
                    map(func(V) = var_pretty(Varmap, V), Captured))
            )
        ]
    ),

    ( if func_get_vartypes(Func, VarTypes) then
        VarTypesPretty = [p_nl_double,
            p_comment(singleton("// "),
                [p_expr([p_str("Types of variables: "), p_nl_soft,
                p_list(pretty_seperated([p_nl_hard],
                    map(var_type_map_pretty(Core, Varmap),
                        to_assoc_list(VarTypes))))])])]
    else
        VarTypesPretty = []
    ),

    % _InfoMap could be printed, but we should also print expression numbers
    % if that's the case.

    Pretty = [p_str("// "),
            p_str(context_string(code_info_context(Expr ^ e_info))),
            p_nl_hard] ++
        [ExprPretty] ++
        CapturedPretty ++ VarTypesPretty.

%-----------------------------------------------------------------------%

:- func var_type_map_pretty(core, varmap, pair(var, type_)) = pretty.

var_type_map_pretty(Core, Varmap, Var - Type) =
        p_expr([VarPretty, p_str(": "), p_nl_soft, TypePretty]) :-
    VarPretty = var_pretty(Varmap, Var),
    TypePretty = type_pretty(Core, Type).

%-----------------------------------------------------------------------%

% Expression numbers are currently unused, and no meta information is
% currently printed about expressions.  As we need it we should consider how
% best to do this.  Or we should print information directly within the
% pretty-printed expression.

% Note that expression nubers start at 0 and are allocated to parents before
% children.  This allows us to avoid printing the number of the first child
% of any expression, which makes pretty printed output less cluttered, as
% these numbers would otherwise appear consecutively in many expressions.
% This must be the same throughout the compiler so that anything
% using expression numbers makes sense when looking at pretty printed
% reports.

:- pred expr_pretty(core::in, varmap::in, expr::in, pretty::out,
    int::in, int::out, map(int, code_info)::in, map(int, code_info)::out)
    is det.

expr_pretty(Core, Varmap, Expr, Pretty, !ExprNum, !InfoMap) :-
    Expr = expr(ExprType, CodeInfo),

    MyExprNum = !.ExprNum,
    !:ExprNum = !.ExprNum + 1,

    det_insert(MyExprNum, CodeInfo, !InfoMap),

    ( ExprType = e_tuple(Exprs),
        map_foldl2(expr_pretty(Core, Varmap), Exprs, ExprsPretty,
            !ExprNum, !InfoMap),
        Pretty = pretty_callish(p_empty, ExprsPretty)
    ; ExprType = e_lets(Lets, In),
        map_foldl2(let_pretty(Core, Varmap), Lets, LetsPretty0,
            !ExprNum, !InfoMap),
        LetsPretty = list_join([p_nl_hard],
            map(func(L) = p_expr(L), LetsPretty0)),
        expr_pretty(Core, Varmap, In, InPretty, !ExprNum, !InfoMap),
        Pretty = p_expr([p_str("let "), p_tabstop] ++
            LetsPretty ++ [p_nl_hard] ++
            [InPretty])
    ; ExprType = e_call(Callee, Args, _),
        ( Callee = c_plain(FuncId),
            CalleePretty = id_pretty(core_lookup_function_name(Core),
                FuncId)
        ; Callee = c_ho(CalleeVar),
            CalleePretty = var_pretty(Varmap, CalleeVar)
        ),
        ArgsPretty = map(func(V) = var_pretty(Varmap, V), Args),
        Pretty = pretty_callish(CalleePretty, ArgsPretty)
    ; ExprType = e_var(Var),
        Pretty = var_pretty(Varmap, Var)
    ; ExprType = e_constant(Const),
        Pretty = const_pretty(core_lookup_function_name(Core),
            core_lookup_constructor_name(Core), Const)
    ; ExprType = e_construction(CtorId, Args),
        PrettyName = id_pretty(core_lookup_constructor_name(Core), CtorId),
        PrettyArgs = map(func(V) = var_pretty(Varmap, V), Args),
        Pretty = pretty_optional_args(PrettyName, PrettyArgs)
    ; ExprType = e_closure(FuncId, Args),
        PrettyFunc = id_pretty(core_lookup_function_name(Core), FuncId),
        PrettyArgs = map(func(V) = var_pretty(Varmap, V), Args),
        Pretty = pretty_callish(p_str("closure"), [PrettyFunc | PrettyArgs])
    ; ExprType = e_match(Var, Cases),
        VarPretty =var_pretty(Varmap, Var),
        map_foldl2(case_pretty(Core, Varmap), Cases, CasesPretty,
            !ExprNum, !InfoMap),
        Pretty = p_group_curly(
            [p_str("match ("), VarPretty, p_str(")")],
            singleton("{"),
            list_join([p_nl_hard], CasesPretty),
            singleton("}"))
    ).

:- pred let_pretty(core::in, varmap::in, expr_let::in, list(pretty)::out,
    int::in, int::out, map(int, code_info)::in, map(int, code_info)::out)
    is det.

let_pretty(Core, Varmap, e_let(Vars, Let), Pretty,
        !ExprNum, !InfoMap) :-
    expr_pretty(Core, Varmap, Let, LetPretty, !ExprNum, !InfoMap),
    ( Vars = [],
        Pretty = [p_str("="), p_spc] ++ [LetPretty]
    ; Vars = [_ | _],
        VarsPretty = list_join([p_str(", "), p_nl_soft],
            map(func(V) = var_pretty(Varmap, V), Vars)),
        Pretty = [p_list(VarsPretty)] ++
            [p_spc, p_nl_soft, p_str("= ")] ++
            [LetPretty]
    ).

:- pred case_pretty(core::in, varmap::in,
    expr_case::in, pretty::out, int::in, int::out,
    map(int, code_info)::in, map(int, code_info)::out) is det.

case_pretty(Core, Varmap, e_case(Pattern, Expr), Pretty, !ExprNum,
        !InfoMap) :-
    PatternPretty = pattern_pretty(Core, Varmap, Pattern),
    expr_pretty(Core, Varmap, Expr, ExprPretty, !ExprNum, !InfoMap),
    Pretty = p_expr([p_str("case "), PatternPretty, p_str(" -> "),
        p_nl_soft, ExprPretty]).

:- func pattern_pretty(core, varmap, expr_pattern) = pretty.

pattern_pretty(_,    _,      p_num(Num)) = p_str(string(Num)).
pattern_pretty(_,    Varmap, p_variable(Var)) =
    var_pretty(Varmap, Var).
pattern_pretty(_,    _,      p_wildcard) = p_str("_").
pattern_pretty(Core, Varmap, p_ctor(CtorId, Args)) =
        pretty_optional_args(NamePretty, ArgsPretty) :-
    NamePretty = id_pretty(core_lookup_constructor_name(Core), CtorId),
    ArgsPretty = map(func(V) = var_pretty(Varmap, V), Args).

%-----------------------------------------------------------------------%

type_pretty(_, builtin_type(Builtin)) = p_str(Str) :-
    builtin_type_name(Builtin, Name),
    Str = q_name_to_string(q_name_append(builtin_module_name, Name)).
type_pretty(_, type_variable(Var)) = p_str(Var).
type_pretty(Core, type_ref(TypeId, Args)) =
    pretty_optional_args(
        id_pretty(core_lookup_type_name(Core), TypeId),
        map(type_pretty(Core), Args)).
type_pretty(Core, func_type(Args, Returns, Uses, Observes)) =
    type_pretty_func_2(Core, p_str("func"), Args, Returns, Uses, Observes).

type_pretty_func(Core, Name, Args, Returns, Uses, Observes) =
        pretty_str([Pretty]) :-
    Pretty = type_pretty_func_2(Core, p_str(Name), Args, Returns,
        Uses, Observes).

:- func type_pretty_func_2(core, pretty, list(type_), list(type_),
    set(resource_id), set(resource_id)) = pretty.

type_pretty_func_2(Core, Name, Args, Returns, Uses, Observes) =
    func_pretty_template(Name, map(type_pretty(Core), Args),
        map(type_pretty(Core), Returns),
        map(resource_pretty(Core), set.to_sorted_list(Uses)),
        map(resource_pretty(Core), set.to_sorted_list(Observes))).

func_pretty_template(Name, Args, Returns, Uses, Observes) = Pretty :-
    ReturnsPretty = maybe_pretty_args_maybe_prefix(
        [p_spc, p_nl_soft, p_str("-> ")], Returns),
    UsesPretty = maybe_pretty_args_maybe_prefix(
        [p_spc, p_nl_soft, p_str("uses ")], Uses),
    ObservesPretty = maybe_pretty_args_maybe_prefix(
        [p_spc, p_nl_soft, p_str("observes ")], Observes),
    Pretty = p_expr([pretty_callish(Name, Args),
        UsesPretty, ObservesPretty, ReturnsPretty]).

%-----------------------------------------------------------------------%

resource_pretty(Core, ResId) =
    p_str(resource_to_string(core_get_resource(Core, ResId))).

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%
