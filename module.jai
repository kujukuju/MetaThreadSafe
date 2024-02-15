get_plugin :: () -> *Metaprogram_Plugin {
    plugin := New(ThreadSafetyPlugin);

    plugin.before_intercept = before_intercept;
    plugin.message = message;
    plugin.shutdown = shutdown;

    return plugin;
}

#scope_module

before_intercept :: (plugin: *Metaprogram_Plugin, flags: *Intercept_Flags) {
    // it seems like flags should be adding checks, not removing them?
    // reducing complexity like this could conflict with other plugins
    // flags.* |= .SKIP_DECLARATIONS | .SKIP_STRUCTS | .SKIP_OTHERS;
}

message :: (metaprogram_plugin: *Metaprogram_Plugin, message: *Message) {
    plugin := cast(*ThreadSafetyPlugin) metaprogram_plugin;

    if message.kind == {
        case .TYPECHECKED;
            typechecked := cast(*Message_Typechecked) message;
            for typechecked_header: typechecked.procedure_headers {
                header := typechecked_header.expression;

                found_unlocked := false;
                found_saftey_check := false;
                for note: header.notes {
                    found_unlocked = found_unlocked || equal_nocase(note.text, "thread_unlocked");
                    found_saftey_check = found_saftey_check || found_unlocked;
                    found_saftey_check = found_saftey_check || equal_nocase(note.text, "thread_isolated");
                    found_saftey_check = found_saftey_check || equal_nocase(note.text, "thread_locked");
                    found_saftey_check = found_saftey_check || equal_nocase(note.text, "thread_safe");
                }

                if found_saftey_check {
                    enclosing_load := header.base.location.enclosing_load;
                    if enclosing_load && enclosing_load.enclosing_import {
                        add_relevant_module(plugin, enclosing_load.enclosing_import);
                    }

                    // if header.polymorph_source_header {
                    //     print("FOOUND POLYMORPH SOURCE: % %\n", header.name, header.polymorph_source_header.*);
                    // }

                    array_add(*plugin.header_idents, header.library_identifier);

                    // if header.polymorph_source_header {
                    //     array_add(*plugin.header_idents, header.polymorph_source_header.library_identifier);
                    // }
                }

                if found_unlocked {
                    stack_path := New(StackPath);
                    stack_path.header = header;
                    array_add(*plugin.unlocked, stack_path);
                }
            }

            for typechecked_body: typechecked.procedure_bodies {
                body := typechecked_body.expression;
                subexpressions := typechecked_body.subexpressions;

                header := body.header;

                table_set(*plugin.body_expressions, body, subexpressions);
                table_set(*plugin.block_expressions, body.block, subexpressions);
                continue;

                array_add(*plugin.header_idents, header.library_identifier);
                if header.polymorph_source_header {
                    array_add(*plugin.header_idents, header.polymorph_source_header.library_identifier);
                }

                if header.procedure_flags & .MACRO {
                    table_set(*plugin.body_expressions, body, subexpressions);
                    continue;
                }

                if !is_relevant_module(plugin, header) {
                    continue;
                }

                found_saftey_check := false;
                for note: header.notes {
                    found_saftey_check = found_saftey_check || equal_nocase(note.text, "thread_unlocked");
                    found_saftey_check = found_saftey_check || equal_nocase(note.text, "thread_isolated");
                    found_saftey_check = found_saftey_check || equal_nocase(note.text, "thread_locked");
                    found_saftey_check = found_saftey_check || equal_nocase(note.text, "thread_safe");
                }

                if !found_saftey_check {
                    continue;
                }

                table_set(*plugin.body_expressions, body, subexpressions);
            }

            for typechecked_all: typechecked.all {
                // print("%\n", typechecked_all.expression.kind);
                if typechecked_all.expression.kind == .PROCEDURE_CALL {
                    procedure_call := cast(*Code_Procedure_Call) typechecked_all.expression;
                    print("found typechecked procedure call %\n\n\n\n", procedure_call.*);
                }

                if typechecked_all.expression.kind == .BLOCK {
                    block := cast(*Code_Block) typechecked_all.expression;
                    print("found typechecked block %\n\n\n\n", block.*);
                }
            }

        case .COMPLETE;
            if plugin.relevant_modules.count > 0 {
                print("Thread safety modules: ");
                for module, index: plugin.relevant_modules {
                    if module.module_name {
                        print("%", module.module_name);
                    } else if module.fully_pathed_filename {
                        print("%", module.fully_pathed_filename);
                    } else {
                        print("%", module.module_type);
                    }

                    if index < plugin.relevant_modules.count - 1 {
                        print(" ");
                    }
                }
                print("\n");
            } else {
                print("No thread safety modules found.\n");
            }

            for stack_path: plugin.unlocked {
                header_body := stack_path.header.body_or_null;
                if !header_body {
                    compiler_report("Thread safety marked header did not have a body.", stack_path.header.location);
                    continue;
                }

                subexpressions, found := table_find(*plugin.body_expressions, header_body);
                if !found {
                    print("Could not find header: %\n", stack_path.header.name);
                    compiler_report("Could not find typechecked code header to complete thread safety check.");
                    continue;
                }

                validate_unlocked(plugin, stack_path.header, subexpressions);
            }
    }
}

shutdown :: (plugin: *Metaprogram_Plugin) {
    using thread_safety_plugin := cast(*ThreadSafetyPlugin) plugin;

    free :: (path: *StackPath) {
        for child: path.children {
            free(child);
        }
        array_free(path.children);
        free(cast(*void) path);
    }

    array_free(relevant_modules);
    for path: unlocked {
        free(path);
    }
    array_free(unlocked);
    deinit(*body_expressions);
    free(plugin);
}

#scope_file

StackPath :: struct {
    parent: *StackPath;
    header: *Code_Procedure_Header;
    children: [..] *StackPath;
}

ThreadSafetyPlugin :: struct {
    #as using base: Metaprogram_Plugin;

    relevant_modules: [..] Message_Import;
    unlocked: [..] *StackPath;
    // im just guessing storing this and looking it up later is actually faster than recursing the tree
    // but maybe there's an internal method to access subexpressions after typechecking has finished?
    body_expressions: Table(*Code_Procedure_Body, [] *Code_Node);
    header_idents: [..] *Code_Ident;
    block_expressions: Table(*Code_Block, [] *Code_Node);
}

validate_unlocked :: (plugin: *ThreadSafetyPlugin, header: *Code_Procedure_Header, subexpressions: [] *Code_Node) -> bool {
    print("checking header % % % %\n\n", header, header.name, header.location.enclosing_load.fully_pathed_filename, header.location.l0);
    for subexpression: subexpressions {
        print("kind %\n\n", subexpression.kind);
        
        if subexpression.kind == .DECLARATION {
            decl := cast(*Code_Declaration) subexpression;
            print("declaration %\n\n", decl.*);
        }

        if subexpression.kind == .PROCEDURE_BODY {
            body := cast(*Code_Procedure_Body) subexpression;
            print("body %\n\n", body.*);

            print("body header % %\n\n", body.header, body.header.*);
            print("body block %\n\n", body.block.*);
        }

        if subexpression.kind != .PROCEDURE_CALL {
            print("Skipping: %\n", subexpression.kind);
            continue;
        }

        subexpression_call := cast(*Code_Procedure_Call) subexpression;
        subexpression_call_header := subexpression_call.resolved_procedure_expression;

        if !subexpression_call_header {
            print("subexpression_call %\n\n", subexpression_call.*);
            print("subexpression_call.procedure_expression %\n\n", subexpression_call.procedure_expression.*);
            ident_pointer := cast(*Code_Ident) subexpression_call.procedure_expression;
            print("ident %\n\n", ident_pointer.*);
            print("found ident? %\n\n", array_find(plugin.header_idents, ident_pointer));
            // compiler_report("Thread safety marked functions cannot make non-compile time function calls, as they cannot be safety checked.", subexpression.location);
            continue;
        }

        if subexpression_call_header.kind != .PROCEDURE_HEADER {
            print("Got a sub expression call that's not a procedure? %\n", subexpression_call.*);
            continue;
        }

        subexpression_header := cast(*Code_Procedure_Header) subexpression_call_header;

        // if it's a macro we just continue passing it down
        if subexpression_header.procedure_flags & .MACRO {
            subexpression_body := subexpression_header.body_or_null;
            if !subexpression_body {
                compiler_report("Thread safety marked macro did not have a body.", subexpression.location);
                return false;
            }

            subexpression_subexpressions, found := table_find(*plugin.body_expressions, subexpression_body);
            if !found {
                if !subexpression_call.macro_expansion_block {
                    print("NO MACRO EXPANSION BLOCK FOR MACRO PROCEDURE HEADER.\n");
                } else {
                    subexpression_subexpressions, found = table_find(*plugin.block_expressions, subexpression_call.macro_expansion_block);
                    print("FOUND MACRO SUBEXPRESSIONS? %\n", found);
                }

                compiler_report("Could not find typechecked macro header to complete thread safety check.");
                return false;
            }

            return validate_unlocked(plugin, subexpression_header, subexpression_subexpressions);
        }

        print("FOUND CALL % %\n\n", subexpression_header.name, subexpression_header.*);

        found_isolated := false;
        found_locked := false;
        found_safe := false;
        for note: subexpression_header.notes {
            if equal_nocase(note.text, "thread_isolated") {
                found_isolated = true;
            } else if equal_nocase(note.text, "thread_locked") {
                found_locked = true;
            } else if equal_nocase(note.text, "thread_safe") {
                found_safe = true;
            }
        }

        if found_isolated {
            subexpression_body := subexpression_header.body_or_null;
            if !subexpression_body {
                compiler_report("Thread safety marked header did not have a body.", subexpression.location);
                return false;
            }

            subexpression_subexpressions, found := table_find(*plugin.body_expressions, subexpression_body);
            if !found {
                compiler_report("Could not find typechecked code header to complete thread safety check.");
                return false;
            }

            if !validate_isolated(plugin, subexpression_header, subexpression_subexpressions) {
                return false;
            }
        } else if found_locked {
            subexpression_body := subexpression_header.body_or_null;
            if !subexpression_body {
                compiler_report("Thread safety marked header did not have a body.", subexpression.location);
                return false;
            }

            subexpression_subexpressions, found := table_find(*plugin.body_expressions, subexpression_body);
            if !found {
                compiler_report("Could not find typechecked code header to complete thread safety check.");
                return false;
            }

            if !validate_locked(plugin, subexpression_header, subexpression_subexpressions) {
                return false;
            }
        } else if found_safe {
            continue;
        } else if is_relevant_module(plugin, subexpression_header) {
            // if it wasn't marked isolated or locked but it's in a relevant module we reject this
            compiler_report("Calling a non-thread safe function from a thread safe function in a thread safety checked module:", subexpression.location);
            return false;
        }
    }

    return true;
}

validate_isolated :: validate_unlocked;

validate_locked :: (plugin: *ThreadSafetyPlugin, header: *Code_Procedure_Header, subexpressions: [] *Code_Node) -> bool {
    // TODO check for weak deadlocks, maybe based on a setting

    found_lock := false;

    for subexpression: subexpressions {
        if subexpression.kind != .PROCEDURE_CALL {
            continue;
        }

        subexpression_call := cast(*Code_Procedure_Call) subexpression;
        subexpression_call_header := subexpression_call.resolved_procedure_expression;

        if !subexpression_call_header {
            compiler_report("Thread safety marked functions cannot make non-compile time function calls, as they cannot be safety checked.", subexpression.location);
            return false;
        }

        if subexpression_call_header.kind != .PROCEDURE_HEADER {
            print("Got a sub expression call that's not a procedure? %\n", subexpression_call.*);
            continue;
        }

        subexpression_header := cast(*Code_Procedure_Header) subexpression_call_header;

        if subexpression_header.name == "lock" || subexpression_header.name == "wait_for" {
            enclosing_load := subexpression_header.base.location.enclosing_load;
            if enclosing_load && enclosing_load.enclosing_import {
                module_name := enclosing_load.enclosing_import.module_name;
                if module_name == "Thread" {
                    found_lock = true;
                    break;
                }
            }
        }
    }

    if !found_lock {
        compiler_report("Thread saftey function marked thread_locked did not contain a mutex lock.", header.location);
        return false;
    }
    
    return true;
}

is_relevant_module :: (plugin: *ThreadSafetyPlugin, header: *Code_Procedure_Header) -> bool {
    enclosing_load := header.base.location.enclosing_load;
    return enclosing_load && enclosing_load.enclosing_import && is_relevant_module(plugin, enclosing_load.enclosing_import);
}

is_relevant_module :: (plugin: *ThreadSafetyPlugin, module: Message_Import) -> bool {
    for relevant: plugin.relevant_modules {
        match := relevant.module_type == module.module_type;
        match = match && relevant.module_name == module.module_name;
        match = match && relevant.fully_pathed_filename == module.fully_pathed_filename;
        if match {
            return true;
        }
    }

    return false;
}

add_relevant_module :: (plugin: *ThreadSafetyPlugin, module: Message_Import) {
    if is_relevant_module(plugin, module) {
        return;
    }

    array_add(*plugin.relevant_modules, module);
}

compiler_report :: (error_text: string, location: Code_Node.Location, mode := Report.ERROR) {
    loc: Source_Code_Location;
    loc.fully_pathed_filename = location.enclosing_load.fully_pathed_filename;
    loc.line_number           = location.l0;
    loc.character_number      = location.c0;

    compiler_report(error_text, loc, mode);
}

#import "Basic";
#import "Compiler";
#import "Hash_Table";
#import "String";