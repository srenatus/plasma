%-----------------------------------------------------------------------%
% Plasma AST
% vim: ts=4 sw=4 et
%
% Copyright (C) 2015-2020 Plasma Team
% Distributed under the terms of the MIT License see ../LICENSE.code
%
% This module represents the AST for plasma programs.
%
%-----------------------------------------------------------------------%
:- module ast.
%-----------------------------------------------------------------------%

:- interface.

:- import_module list.
:- import_module maybe.

:- import_module common_types.
:- import_module context.
:- import_module q_name.
:- import_module varmap.

:- type ast == ast(ast_entry).
:- type ast(E)
    --->    ast(
                a_module_name       :: q_name,
                % Context of module declaration.
                a_context           :: context,
                a_entries           :: list(E)
            ).

% AST for include files.
:- type ast_interface == ast(ast_interface_entry).

:- type ast_entry
    --->    ast_import(ast_import)
    ;       ast_type(nq_name, ast_type)
    ;       ast_resource(nq_name, ast_resource)
    ;       ast_function(nq_name, ast_function).

    % This isn't actually used in the ASt but in a few things that
    % work with the AST so define it here.
:- type named(E)
    --->    named(nq_name, E).

:- type ast_interface_entry
    --->    asti_function(q_name, ast_function_decl).

:- type ast_import
    --->    ast_import(
                ai_names            :: import_name,
                ai_as               :: maybe(string),
                ai_context          :: context
            ).

:- type ast_type
    --->    ast_type(
                at_params           :: list(string),
                at_costructors      :: list(at_constructor),
                at_context          :: context
            ).

:- type ast_resource
    --->    ast_resource(
                ar_from             :: q_name
            ).

:- type ast_function_decl
    --->    ast_function_decl(
                afd_params          :: list(ast_param),
                afd_return          :: list(ast_type_expr),
                afd_uses            :: list(ast_uses),
                afd_context         :: context
            ).

:- type ast_function
    --->    ast_function(
                af_decl             :: ast_function_decl,
                af_body             :: list(ast_block_thing),
                af_export           :: sharing
            ).

:- type ast_block_thing(Info)
    --->    astbt_statement(ast_statement(Info))
    ;       astbt_function(nq_name, ast_function).

:- type ast_block_thing == ast_block_thing(context).

%
% Modules, imports and exports.
%
:- type export_some_or_all
    --->    export_some(list(string))
    ;       export_all.

:- type import_name
    --->    dot(string, import_name_2).

:- type import_name_2
    --->    nil
    ;       star
    ;       dot(string, import_name_2).

%
% Types
%
:- type at_constructor
    --->    at_constructor(
                atc_name        :: nq_name,
                atc_args        :: list(at_field),
                atc_context     :: context
            ).

:- type at_field
    --->    at_field(
                atf_name        :: string,
                atf_type        :: ast_type_expr,
                atf_context     :: context
            ).

:- type ast_type_expr
    --->    ast_type(
                ate_name            :: q_name,
                ate_args            :: list(ast_type_expr),
                ate_context         :: context
            )
    ;       ast_type_func(
                atf_args            :: list(ast_type_expr),
                atf_returns         :: list(ast_type_expr),
                atf_uses            :: list(ast_uses),
                atf_context_        :: context
            )
    ;       ast_type_var(
                atv_name            :: string,
                atv_context         :: context
            ).

%
% Code signatures
%
:- type ast_param
    --->    ast_param(
                ap_name             :: var_or_wildcard(string),
                ap_type             :: ast_type_expr
            ).

:- type ast_uses
    --->    ast_uses(
                au_uses_type        :: uses_type,
                au_name             :: q_name
            ).

:- type uses_type
    --->    ut_uses
    ;       ut_observes.

%
% Code
%
:- type ast_statement(Info)
    --->    ast_statement(
                ast_stmt_type       :: ast_stmt_type(Info),
                ast_stmt_info       :: Info
            ).

:- type ast_statement == ast_statement(context).

:- type ast_stmt_type(Info)
            % A statement that looks like a call must be a call, it cannot
            % be a construction as that would have no effect.
    --->    s_call(ast_call_like)
    ;       s_assign_statement(
                as_ast_vars         :: list(var_or_wildcard(string)),
                as_expr             :: ast_expression
            )
    ;       s_array_set_statement(
                sas_array           :: string,
                sas_subscript       :: ast_expression,
                sas_rhs             :: ast_expression
            )
    ;       s_return_statement(list(ast_expression))
    ;       s_vars_statement(
                vs_vars             :: list(var_or_wildcard(string)),
                vs_expr             :: maybe(ast_expression)
            )
    ;       s_match_statement(
                sms_expr            :: ast_expression,
                sms_cases           :: list(ast_match_case(Info))
            )
    ;       s_ite(
                psi_cond            :: ast_expression,
                psi_then            :: list(ast_block_thing(Info)),
                psi_else            :: list(ast_block_thing(Info))
            ).

:- type ast_match_case(Info)
    --->    ast_match_case(
                c_pattern           :: ast_pattern,
                c_stmts             :: list(ast_block_thing(Info))
            ).

:- type ast_match_case == ast_match_case(context).

:- type ast_expression
    --->    e_call_like(
                ec_call_like        :: ast_call_like
            )
    ;       e_u_op(
                euo_op              :: ast_uop,
                euo_expr            :: ast_expression
            )
    ;       e_b_op(
                ebo_expr_left       :: ast_expression,
                ebo_op              :: ast_bop,
                ebo_expr_right      :: ast_expression
            )
    ;       e_symbol(
                es_name             :: q_name
            )
    ;       e_const(
                ec_value            :: ast_const
            )
    ;       e_array(
                ea_values           :: list(ast_expression)
            ).

:- type ast_uop
    --->    u_minus
    ;       u_not.

:- type ast_bop
    --->    b_add
    ;       b_sub
    ;       b_mul
    ;       b_div
    ;       b_mod
    ;       b_lt
    ;       b_gt
    ;       b_lteq
    ;       b_gteq
    ;       b_eq
    ;       b_neq
    ;       b_logical_and
    ;       b_logical_or
    ;       b_concat
    ;       b_list_cons
    ;       b_array_subscript.

:- type ast_const
    --->    c_number(int)
    ;       c_string(string)
    ;       c_list_nil.

    % A call or call-like thing (such as a construction).
    %
:- type ast_call_like
    --->    ast_call_like(
                ec_callee           :: ast_expression,
                ec_args             :: list(ast_expression)
            )
    ;       ast_bang_call(
                ebc_callee          :: ast_expression,
                ebc_args            :: list(ast_expression)
            ).

:- type ast_pattern
    --->    p_constr(string, list(ast_pattern))
    ;       p_number(int)
    ;       p_wildcard
    ;       p_var(string)
    ;       p_list_nil
    ;       p_list_cons(ast_pattern, ast_pattern).

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%
