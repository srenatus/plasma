%-----------------------------------------------------------------------%
% Plasma parser
% vim: ts=4 sw=4 et
%
% Copyright (C) 2015 Paul Bone
% Distributed under the terms of the GPLv2 see ../LICENSE.tools
%
% This program compiles plasma modules.
%
%-----------------------------------------------------------------------%
:- module parse.
%-----------------------------------------------------------------------%

:- interface.

:- import_module io.
:- import_module string.

:- import_module ast.
:- import_module result.
:- import_module lex_util.

%-----------------------------------------------------------------------%

:- pred parse(string::in, result(plasma_ast, read_src_error)::out,
    io::di, io::uo) is det.

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%

:- implementation.

:- import_module int.
:- import_module list.
:- import_module maybe.
:- import_module require.

:- import_module ast.
:- import_module context.
:- import_module lex.
:- import_module parsing.
:- import_module parsing.bnf.
:- import_module symtab.

%-----------------------------------------------------------------------%

parse(Filename, Result, !IO) :-
    parse_file(Filename, lexemes, ignore_tokens, plasma_bnf, Result0, !IO),
    ( Result0 = ok(PNode),
        ( PNode = module_(AST) ->
            Result = ok(AST)
        ;
            unexpected($file, $pred, "Wrong node type")
        )
    ; Result0 = errors(Errors),
        Result = errors(Errors)
    ).

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%

:- type token_type
    --->    module_
    ;       import
    ;       using
    ;       observing
    ;       ident
    ;       string
    ;       l_curly
    ;       r_curly
    ;       l_paren
    ;       r_paren
    ;       semicolon
    ;       colon
    ;       comma
    ;       period
    ;       arrow
    ;       bang
    ;       newline
    ;       comment
    ;       whitespace
    ;       eof.

:- func lexemes = list(lexeme(lex_token(token_type))).

lexemes = [
        ("module"           -> return_simple(module_)),
        ("import"           -> return_simple(import)),
        ("using"            -> return_simple(using)),
        ("observing"        -> return_simple(observing)),
        ("{"                -> return_simple(l_curly)),
        ("}"                -> return_simple(r_curly)),
        ("("                -> return_simple(l_paren)),
        (")"                -> return_simple(r_paren)),
        (";"                -> return_simple(semicolon)),
        (":"                -> return_simple(colon)),
        (","                -> return_simple(comma)),
        ("."                -> return_simple(period)),
        ("->"               -> return_simple(arrow)),
        ("!"                -> return_simple(bang)),
        (lex.identifier     -> return_string(ident)),
        % TODO: escapes
        ("\"" ++ *(anybut("\"")) ++ "\""
                            -> (func(S0) = lex_token(string, yes(S)) :-
                                    between(S0, 1, length(S0) - 1, S))),

        (("#" ++ *(anybut("\n")))
                            -> return_simple(comment)),
        ("\n"               -> return_simple(newline)),
        (any(" \t\v\f")     -> return_simple(whitespace))
    ].

:- pred ignore_tokens(lex_token(token_type)::in) is semidet.

ignore_tokens(lex_token(whitespace, _)).
ignore_tokens(lex_token(newline, _)).
ignore_tokens(lex_token(comment, _)).

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%

:- type non_terminal
    --->    module_
    ;       module_decl
    ;       export_list
    ;       export_list_continue
    ;       toplevel_items
    ;       toplevel_item
    ;       import_directive

    ;       proc_defn
    ;       proc_param_list
    ;       maybe_using
    ;       resource_list
    ;       resource_list_cont

    ;       block
    ;       statements
    ;       statement

    ;       expr
    ;       expr_part1
    ;       expr_part2
    ;       call_arg_list
    ;       call_arg_list_cont

    ;       type_expr
    ;       type_
    ;       maybe_type_parameters
    ;       type_parameters.

:- func plasma_bnf = bnf(token_type, non_terminal, pt_node).

plasma_bnf = bnf(module_, eof,
    [
        % I will show the EBNF in comments.  NonTerminals appear in
        % CamelCase and terminals appear in lower_underscore_case.
        %
        % Plasma := ModuleDecl ToplevelItem*
        %
        bnf_rule("module", module_, [
            bnf_rhs([nt(module_decl), nt(toplevel_items)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [module_decl(Name, MaybeExports),
                        toplevel_items(Items)],
                    Node = module_(plasma_ast(Name, MaybeExports, Items))
                ))
            )
        ]),

        % ModuleDecl := module ident ( '{' ident ( , ident )* '}' )?
        bnf_rule("module decl", module_decl, [
            bnf_rhs([t(module_), t(ident), nt(export_list)],
                (func(Nodes) =
                    ( Nodes = [_, ident(Name), nil] ->
                        yes(module_decl(Name, no))
                    ; Nodes = [_, ident(Name), export_list(List)] ->
                        yes(module_decl(Name, yes(List)))
                    ;
                        no
                    )
                ))
            ]),
        bnf_rule("export list", export_list, [
            bnf_rhs(
                [t(l_curly), t(ident), nt(export_list_continue), t(r_curly)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [_, ident(X), export_list(Xs), _],
                    Node = export_list([X | Xs])
                ))
            ),
            bnf_rhs([], const(nil))
        ]),
        bnf_rule("export list continue", export_list_continue, [
            bnf_rhs([t(comma), t(ident), nt(export_list_continue)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [_, ident(X), export_list(Xs)],
                    Node = export_list([X | Xs])
                ))
            ),
            bnf_rhs([],
                const(export_list([])))
        ]),

        bnf_rule("toplevel items", toplevel_items, [
            bnf_rhs([],
                const(toplevel_items([]))),
            bnf_rhs([nt(toplevel_item), nt(toplevel_items)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [toplevel_item(X), toplevel_items(Xs)],
                    Node = toplevel_items([X | Xs])
                ))
            )
        ]),

        % ToplevelItem := ImportDirective
        %               | ProcDefinition
        bnf_rule("toplevel item", toplevel_item, [
            bnf_rhs([nt(import_directive)], identity),
            bnf_rhs([nt(proc_defn)], identity)
        ]),

        % ImportDirective := import ident
        bnf_rule("import directive", import_directive, [
            bnf_rhs([t(import), t(ident)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [_, ident(Name)],
                    Node = toplevel_item(past_import(symbol(Name)))
                ))
            )
        ]),

        % ProcDefinition := ident '(' ( Param ( , Param )* )? ')' ->
        %                       TypeExpr Using* Block
        % Param := ident : TypeExpr
        % Using := using ident ( , ident )*
        %        | observing ident ( , ident )*
        bnf_rule("proc definition", proc_defn, [
            bnf_rhs([t(ident), t(l_paren), nt(proc_param_list), t(r_paren),
                    t(arrow), nt(type_expr), nt(maybe_using), nt(block)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [ident(Name), _, param_list(Params), _, _,
                        type_(RetType), using(Using), block(Body)],
                    Node = toplevel_item(past_function(symbol(Name),
                        Params, RetType, Using, Body))
                ))
            )
        ]),
        bnf_rule("argument list", proc_param_list, [
            bnf_rhs([], const(param_list([]))),
            bnf_rhs([t(ident), t(colon), nt(type_expr), nt(proc_param_list)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [ident(Name), _, type_(Type),
                        param_list(Params)],
                    Node = param_list([past_param(Name, Type) | Params])
                ))
            )
        ]),
        bnf_rule("maybe using", maybe_using, [
            bnf_rhs([], const(using([]))),
            bnf_rhs([t(using), nt(resource_list), nt(maybe_using)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [_, resources(Resources), using(UsingB)],
                    UsingA = map((func(N) = past_using(ut_using, N)),
                        Resources),
                    Node = using(UsingA ++ UsingB)
                ))
            )
        ]),
        bnf_rule("resource list", resource_list, [
            bnf_rhs([t(ident), nt(resource_list_cont)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [ident(Res), resources(Ress)],
                    Node = resources([Res | Ress])
                ))
            )
        ]),
        bnf_rule("resource list", resource_list_cont, [
            bnf_rhs([], const(resources([]))),
            bnf_rhs([t(comma), t(ident), nt(resource_list_cont)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [_, ident(Res), resources(Ress)],
                    Node = resources([Res | Ress])
                ))
            )
        ]),

        % TypeExpr := Type
        %           | Type '(' TypeExpr ( , TypeExpr )* ')'
        % Type := ident
        bnf_rule("type expression", type_expr, [
            bnf_rhs([nt(type_), nt(maybe_type_parameters)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [ident(TypeName), type_params(Params)],
                    Node = type_(past_type(TypeName, Params))
                ))
            )
        ]),
        bnf_rule("type expression", maybe_type_parameters, [
            bnf_rhs([], const(type_params([]))),
            bnf_rhs([t(l_paren), nt(type_expr), nt(type_parameters),
                    t(r_paren)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [_, type_(Type), type_params(Types), _],
                    Node = type_params([Type | Types])
                ))
            )
        ]),
        bnf_rule("type expression", type_parameters, [
            bnf_rhs([], const(type_params([]))),
            bnf_rhs([t(comma), nt(type_expr), nt(type_parameters)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [_, type_(Type), type_params(Types)],
                    Node = type_params([Type | Types])
                ))
            )
        ]),
        bnf_rule("type", type_, [
            bnf_rhs([t(ident)], identity)
        ]),

        % Block := '{' Statement* '}'
        bnf_rule("block", block, [
            bnf_rhs([t(l_curly), nt(statement), nt(statements), t(r_curly)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [_, stmt(Stmt), block(Stmts), _],
                    Node = block([Stmt | Stmts])
                ))
            )
        ]),
        bnf_rule("block", statements, [
            bnf_rhs([], const(block([]))),
            bnf_rhs([nt(statement), nt(statements)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [stmt(Stmt), block(Stmts)],
                    Node = block([Stmt | Stmts])
                ))
            )
        ]),

        % Statement := '!' Statement
        %            | Expr
        bnf_rule("statement", statement, [
            bnf_rhs([t(bang), nt(statement)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [_, stmt(Stmt)],
                    Node = stmt(ps_bang_statement(Stmt))
                ))
            ),
            bnf_rhs([nt(expr)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [expr(Expr)],
                    Node = stmt(ps_expr_statement(Expr))
                ))
            )
        ]),

        % Expressions may be:
        % A value:
        %   Expr := ident
        % A constant:
        %         | const_str
        % A call:
        %         | Expr '(' Expr ( , Expr )* ')'
        %
        % Due to the syntax of calls this is left recursive and requires
        % more than 1 lookahead.  We have broken expr into two non
        % terminals, the first parses most expressions, the second parses
        % the arguments to a call and may be empty.
        %
        bnf_rule("expression", expr, [
            bnf_rhs([nt(expr_part1), nt(expr_part2)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    ( Nodes = [expr(Expr), nil],
                        Node = expr(Expr)
                    ; Nodes = [expr(Expr), arg_list(Exprs)],
                        Node = expr(pe_call(Expr, Exprs))
                    )
                ))
            )
        ]),
        bnf_rule("expression", expr_part1, [
            bnf_rhs([t(ident)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [ident(Name)],
                    Node = expr(pe_variable(Name))
                ))
            ),
            bnf_rhs([t(string)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [string(String)],
                    Node = expr(pe_const(pc_string(String)))
                ))
            )
        ]),
        bnf_rule("expression", expr_part2, [
            bnf_rhs([], const(nil)),
            bnf_rhs([t(l_paren), nt(call_arg_list), t(r_paren)],
                identity_nth(2))
        ]),
        bnf_rule("argument list", call_arg_list, [
            bnf_rhs([], const(arg_list([]))),
            bnf_rhs([nt(expr), nt(call_arg_list_cont)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [expr(Expr), arg_list(Exprs)],
                    Node = arg_list([Expr | Exprs])
                ))
            )
        ]),
        bnf_rule("argument list", call_arg_list_cont, [
            bnf_rhs([], const(arg_list([]))),
            bnf_rhs([t(comma), nt(expr), nt(call_arg_list_cont)],
                det_func((pred(Nodes::in, Node::out) is semidet :-
                    Nodes = [_, expr(Expr), arg_list(Exprs)],
                    Node = arg_list([Expr | Exprs])
                ))
            )
        ])
    ]).

:- type pt_node
    --->    module_(plasma_ast)
    ;       module_decl(string, maybe(list(string)))
    ;       export_list(list(string))
    ;       toplevel_items(list(past_entry))
    ;       toplevel_item(past_entry)
    ;       param_list(list(past_param))
    ;       type_(past_type)
    ;       type_params(list(past_type))
    ;       using(list(past_using))
    ;       resources(list(string))
    ;       block(list(past_statement))
    ;       stmt(past_statement)
    ;       expr(past_expression)
    ;       arg_list(list(past_expression))
    ;       ident(string)
    ;       string(string)
    ;       nil.

:- instance token_to_result(token_type, pt_node) where [
        token_to_result(Type, MaybeString, _) =
            ( Type = ident, MaybeString = yes(String) ->
                ident(String)
            ; Type = string, MaybeString = yes(String) ->
                % TODO: handle escape sequences.
                string(String)
            ;
                nil
            )
    ].

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%
