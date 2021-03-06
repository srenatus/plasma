%-----------------------------------------------------------------------%
% vim: ts=4 sw=4 et
%-----------------------------------------------------------------------%
:- module pre.import.
%
% Copyright (C) 2020 Plasma Team
% Distributed under the terms of the MIT License see ../LICENSE.code
%
% Process imports by reading interface files.
%
%-----------------------------------------------------------------------%

:- interface.

:- import_module io.
:- import_module list.

:- import_module ast.
:- import_module compile_error.
:- import_module core.
:- import_module pre.env.
:- import_module util.
:- import_module util.log.
:- import_module util.result.

%-----------------------------------------------------------------------%

    % ast_to_core_imports(Verbose, ImportEnv, Imports, !Env, !Core, !Errors,
    %   !IO).
    %
    % The ImportEnv is the Env that should be used to read interface files,
    % while !Env is a different environment to be updated with the results.
    %
:- pred ast_to_core_imports(log_config::in, env::in, list(ast_import)::in,
    env::in, env::out, core::in, core::out,
    errors(compile_error)::in, errors(compile_error)::out, io::di, io::uo)
    is det.

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%
:- implementation.

:- import_module assoc_list.
:- import_module bool.
:- import_module cord.
:- import_module map.
:- import_module maybe.
:- import_module pair.
:- import_module require.
:- import_module set.
:- import_module string.

:- import_module common_types.
:- import_module constant.
:- import_module context.
:- import_module core.function.
:- import_module parse.
:- import_module parse_util.
:- import_module pre.ast_to_core.
:- import_module q_name.
:- import_module util.exception.
:- import_module util.io.
:- import_module util.path.

%-----------------------------------------------------------------------%

ast_to_core_imports(Verbose, ReadEnv, Imports, !Env, !Core, !Errors, !IO) :-
    get_dir_list(MaybeDirList, !IO),
    ( MaybeDirList = ok(DirList),
        % Read the imports and convert it to core representation.
        ModuleNames = sort_and_remove_dups(map(imported_module, Imports)),
        foldl3(read_import(Verbose, DirList, ReadEnv), ModuleNames, init,
            ImportMap, !Core, !IO),

        % Enrol the imports in the environment.
        foldl4(process_import(Verbose, ImportMap), Imports, init, _, !Env,
            !Errors, !IO)
    ; MaybeDirList = error(Error),
        compile_error($file, $pred,
            "IO error while searching for modules: " ++ Error)
    ).

:- func imported_module(ast_import) = q_name.

imported_module(Import) = import_name_to_module_name(Import ^ ai_names).

%-----------------------------------------------------------------------%

:- type import_map == map(q_name, import_result).

:- type import_result
    --->    ok(assoc_list(q_name, func_id))
    ;       read_error(compile_error)
    ;       compile_errors(errors(compile_error)).

    % Read an import and convert it to core representation, store references
    % to it in the import map.
    %
:- pred read_import(log_config::in, list(string)::in, env::in, q_name::in,
    import_map::in, import_map::out, core::in, core::out,
    io::di, io::uo) is det.

read_import(Verbose, DirList, Env, ModuleName, !ImportMap, !Core, !IO) :-
    find_interface(DirList, ModuleName, MaybeFilename, !IO),
    ( MaybeFilename = ok(Filename),
        verbose_output(Verbose,
            format("Reading %s from %s\n",
                [s(q_name_to_string(ModuleName)), s(Filename)]),
            !IO),
        parse_interface(Filename, MaybeAST, !IO),
        ( MaybeAST = ok(AST),
            ( if AST ^ a_module_name = ModuleName then
                map2_foldl(read_import_2(ModuleName, Env), AST ^ a_entries,
                    NamePairs, Errors0, !Core),
                Errors = cord_list_to_cord(Errors0),
                ( if is_empty(Errors) then
                    Result = ok(NamePairs)
                else
                    Result = compile_errors(Errors)
                )
            else
                Result = compile_errors(error(AST ^ a_context,
                    ce_interface_contains_wrong_module(
                        Filename, ModuleName, AST ^ a_module_name)))
            )
        ; MaybeAST = errors(Errors),
            Result = compile_errors(
                map(func(error(C, E)) = error(C, ce_read_source_error(E)),
                    Errors))
        )
    ; MaybeFilename = error(Error),
        Result = read_error(Error)
    ),
    det_insert(ModuleName, Result, !ImportMap).

:- pred read_import_2(q_name::in, env::in, ast_interface_entry::in,
    pair(q_name, func_id)::out, errors(compile_error)::out,
    core::in, core::out) is det.

read_import_2(ModuleName, Env, asti_function(Name, Decl), NamePair, Errors,
        !Core) :-
    core_allocate_function(FuncId, !Core),

    ( if q_name_append(ModuleName, _, Name) then
        true
    else
        unexpected($file, $pred,
            "Imported module exports symbols of other module")
    ),
    NamePair = Name - FuncId,

    % Imported functions aren't re-exported, so we annotate it with
    % s_private.
    ast_to_func_decl(!.Core, Env, Name, Decl, s_private, Result),
    ( Result = ok(Function0),
        func_set_imported(Function0, Function),
        core_set_function(FuncId, Function, !Core),
        Errors = init
    ; Result = errors(Errors)
    ).

    % Find the interface on the disk. For now we look in the current
    % directory only, later we'll implement include paths.
    %
:- pred find_interface(list(string)::in, q_name::in,
    maybe_error(string, compile_error)::out, io::di, io::uo) is det.

find_interface(DirList, ModuleName, Result, !IO) :-
    filter(matching_interface_file(ModuleName), DirList, Matches),
    ( Matches = [],
        Result = error(ce_module_not_found(ModuleName))
    ; Matches = [FileName],
        Result = ok(FileName)
    ; Matches = [_, _ | _],
        compile_error($file, $pred, "Ambigious interfaces found")
    ).

:- pred matching_interface_file(q_name::in, string::in) is semidet.

matching_interface_file(ModuleName, FileName) :-
    filename_extension(interface_extension, FileName, FileNameBase),
    strip_file_name_punctuation(q_name_to_string(ModuleName)) =
        strip_file_name_punctuation(FileNameBase).

%-----------------------------------------------------------------------%

    % Enrol an import in the import_map into the environment.
    %
    % IO is used only for logging.
    %
:- pred process_import(log_config::in, import_map::in, ast_import::in,
    set(q_name)::in, set(q_name)::out, env::in, env::out,
    errors(compile_error)::in, errors(compile_error)::out,
    io::di, io::uo) is det.

process_import(Verbose, ImportMap, ast_import(ImportName, _AsName, Context),
        !ReadSet, !Env, !Errors, !IO) :-
    ModuleName = import_name_to_module_name(ImportName),

    verbose_output(Verbose,
        format("Importing %s for %s\n",
            [s(q_name_to_string(ModuleName)), s(string(ImportName))]), !IO),

    ( if insert_new(ModuleName, !ReadSet) then
        true
    else
        add_error(Context, ce_import_would_clobber(ModuleName), !Errors)
    ),

    map.lookup(ImportMap, ModuleName, ReadResult),
    ( ReadResult = ok(NamePairs),
        foldl(import_add_to_env, NamePairs, !Env)
    ; ReadResult = read_error(Error),
        add_error(Context, Error, !Errors)
    ; ReadResult = compile_errors(Errors),
        add_errors(Errors, !Errors)
    ).

:- pred import_add_to_env(pair(q_name, func_id)::in, env::in, env::out) is det.

import_add_to_env(Name - FuncId, !Env) :-
    ( if env_add_func(Name, FuncId, !Env) then
        true
    else
        % XXX Needs to be context of import directive, we'll do a proper
        % error later.
        compile_error($file, $pred, "Name collision caused by import")
    ).

%-----------------------------------------------------------------------%

:- func import_name_to_module_name(import_name) = q_name.

import_name_to_module_name(dot(First, Rest)) = Name :-
    ( ( Rest = nil
      ; Rest = star
      ),
      Name = q_name_from_dotted_string(First)
    ; Rest = dot(_, _),
        util.exception.sorry($file, $pred, "Submodules")
    ).

%-----------------------------------------------------------------------%
%-----------------------------------------------------------------------%
