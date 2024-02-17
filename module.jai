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
            start := seconds_since_init();
            defer plugin.duration += seconds_since_init() - start;

            typechecked := cast(*Message_Typechecked) message;
            for typechecked_header: typechecked.procedure_headers {
                header := typechecked_header.expression;

                found_unlocked := false;
                found_saftey_check := false;
                for note: header.notes {
                    found_unlocked = found_unlocked || begins_with_nocase(note.text, "thread_unlocked");
                    found_saftey_check = found_saftey_check || found_unlocked;
                    found_saftey_check = found_saftey_check || equal_nocase(note.text, "thread_isolated");
                    found_saftey_check = found_saftey_check || equal_nocase(note.text, "thread");
                    found_saftey_check = found_saftey_check || equal_nocase(note.text, "thread_safe");
                }

                if found_saftey_check {
                    enclosing_load := header.base.location.enclosing_load;
                    if enclosing_load && enclosing_load.enclosing_import {
                        add_relevant_module(plugin, enclosing_load.enclosing_import);
                    }

                    // if we found a header that's already unique, now it's vague
                    unique_header, unique_index := find_marked_unique_header(plugin, header.name);
                    if unique_header {
                        array_unordered_remove_by_index(*plugin.marked_unique_headers, unique_index);

                        table_set(*plugin.vague_headers, header.name, true);
                    } else {
                        array_add(*plugin.marked_unique_headers, header);
                    }
                } else {
                    // by not having a thread mode the function is automatically vague
                    if !table_contains(*plugin.vague_headers, header.name) {
                        table_set(*plugin.vague_headers, header.name, true);

                        unique_header, unique_index := find_marked_unique_header(plugin, header.name);
                        if unique_header {
                            array_unordered_remove_by_index(*plugin.marked_unique_headers, unique_index);
                        }
                    }
                }

                if found_unlocked {
                    #if DEBUG then print("Found thread_unlocked: %\n", header.name);
                    array_add(*plugin.unlocked, header);
                }
            }

        case .COMPLETE;
            start := seconds_since_init();
            defer plugin.duration += seconds_since_init() - start;

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

            locked_mutexes: [..] *Code_Node;
            locked_mutexes.allocator = temp;

            for header: plugin.unlocked {
                if !header.body_or_null {
                    compiler_report(plugin, "Thread safety marked header did not have a body.", header.location);
                    return;
                }

                unlocked_string: string;
                for note: header.notes {
                    if begins_with_nocase(note.text, "thread_unlocked") {
                        unlocked_string = note.text;
                    }
                }

                no_name_count :: "thread_unlocked".count;

                unlocked_name: string;
                if unlocked_string.count >= no_name_count + 2 && unlocked_string[no_name_count] == #char "(" && unlocked_string[unlocked_string.count - 1] == #char ")" {
                    unlocked_name.data = unlocked_string.data + no_name_count + 1;
                    unlocked_name.count = unlocked_string.count - no_name_count - 2;
                }

                unlocked_name = to_lower_copy_new(unlocked_name,, allocator = temp);

                // TODO this could technically fail in some scenarios where you're entering the same function through 2 different routes within the same name
                // in that case, it would only traverse the given function once, while the mutex locks could be different in both scenarios
                visited := find_or_add(*plugin.visited, unlocked_name);
                mutex_options := find_or_add(*plugin.mutex_options, unlocked_name);
                locked_mutexes.count = 0;

                table_set(visited, header.body_or_null, true);

                if !validate_unlocked(plugin, header.body_or_null, visited, mutex_options, *locked_mutexes, maybe_tprint("%_%", header.name, header.kind)) {
                    return;
                }

                if locked_mutexes.count > 0 {
                    for locked_mutex: locked_mutexes {
                        compiler_report(plugin, "Finished checking the whole unlocked thread stack, but found remaining locked mutexes. This implies either there's complicated mutex lock/unlock logic that calls back into previous stack methods and we can't handle this, or a single method that locks/unlocks a mutex has already been visited and won't be visited again with how the recursive logic is currently set up, and this is potentially fixable.", locked_mutex.location, .ERROR_CONTINUABLE);
                    }
                }
            }

            if plugin.failed {
                compiler_set_workspace_status(.FAILED, plugin.workspace);
            }
    }
}

shutdown :: (plugin: *Metaprogram_Plugin) {
    using thread_safety_plugin := cast(*ThreadSafetyPlugin) plugin;

    print("Thread safety check took % seconds.\n", duration);

    // array_free(relevant_modules);
    // array_free(unlocked);
    // deinit(*visited);
    // array_free(marked_unique_headers);
    // deinit(*vague_headers);
    // free(plugin);
}

#scope_file

DEBUG :: false;

ThreadSafetyPlugin :: struct {
    #as using base: Metaprogram_Plugin;

    relevant_modules: [..] Message_Import;
    unlocked: [..] *Code_Procedure_Header;
    // TODO should just actually use stack path for this so it's also easy to check dead lock
    visited: Table(string, Table(*Code_Node, bool));
    // TODO this is a temporary measure until I figure out how to continue traversal past a for_expansion
    marked_unique_headers: [..] *Code_Procedure_Header;
    vague_headers: Table(string, bool);
    mutex_options: Table(string, Table(*Code_Procedure_Header, [..] *Code_Node));
    recycled_subexpressions: [..] [..] *Code_Node;
    duration: float64;
    failed: bool;
}

validate_unlocked :: (plugin: *ThreadSafetyPlugin, node: *Code_Node, visited: *Table(*Code_Node, bool), mutex_options: *Table(*Code_Procedure_Header, [..] *Code_Node), locked_mutexes: *[..] *Code_Node, identifier: string = "", precursor: string = "") -> bool {
    #if DEBUG then print("\n");
    #if DEBUG then print(precursor);
    #if DEBUG then print("Validating: %\n", identifier);

    subexpressions: [..] *Code_Node;
    if plugin.recycled_subexpressions.count > 0 {
        subexpressions = plugin.recycled_subexpressions[plugin.recycled_subexpressions.count - 1];
        plugin.recycled_subexpressions.count -= 1;
    }
    defer array_add(*plugin.recycled_subexpressions, subexpressions);

    subexpressions.count = 0;
    get_subexpressions(node, *subexpressions);

    normal_index := 0;
    deferred_index := subexpressions.count - 1;

    // move deferred to the back in place
    for i: 0..subexpressions.count - 1 {
        if subexpressions[normal_index].kind == .DEFER {
            deferred := subexpressions[normal_index];
            for a: normal_index..deferred_index - 1 {
                subexpressions[a] = subexpressions[a + 1];
            }
            subexpressions[deferred_index] = deferred;
            deferred_index -= 1;
        } else {
            normal_index += 1;
        }
    }

    #if DEBUG {
        print(precursor);
        print("Subexpressions: ");
        for subexpression: subexpressions {
            print("% ", subexpression.kind);
        }
        print("\n");
    }

    for subexpression: subexpressions {
        if table_contains(visited, subexpression) {
            continue;
        }

        table_set(visited, subexpression, true);

        #if DEBUG then print(precursor);
        #if DEBUG then print("\tKind: %\n", subexpression.kind);

        #if DEBUG {
            if subexpression.kind == .PROCEDURE_CALL {
                print(precursor);
                print("\tCall: %\n", (cast(*Code_Procedure_Call) subexpression).*);
                call_expression := (cast(*Code_Procedure_Call) subexpression).procedure_expression;
                if call_expression {
                    print(precursor);
                    print("\tCall expression: %\n", call_expression.*);

                    if call_expression.kind == .IDENT {
                        print(precursor);
                        print("\tCall ident: %\n", (cast(*Code_Ident) call_expression).*);
                    }
                }

                call_resolved_expression := (cast(*Code_Procedure_Call) subexpression).resolved_procedure_expression;
                if call_resolved_expression {
                    print(precursor);
                    print("\tResolved call expression: %\n", call_resolved_expression.*);

                    if call_resolved_expression.kind == .PROCEDURE_HEADER {
                        print(precursor);
                        print("\t\tResolved call header: %\n", (cast(*Code_Procedure_Header) call_resolved_expression).*);

                        for note: (cast(*Code_Procedure_Header) call_resolved_expression).notes {
                            print("\n");
                            print(precursor);
                            print("\tFound note: %\n\n", note.text);
                        }
                    }
                }
            }
        }

        if subexpression.kind == .PROCEDURE_CALL {
            subexpression_call := cast(*Code_Procedure_Call) subexpression;
            call_expression := subexpression_call.procedure_expression;
            if call_expression && call_expression.kind == .PROCEDURE_HEADER {
                // this can be like a #run () -> {}() thing
                // compiler_report(plugin, "Got a non-resolved procedure expression that's a header? I must not understand something...", subexpression.location);
                continue;
                // return false;
            }

            resolved_call_expression := subexpression_call.resolved_procedure_expression;
            if !resolved_call_expression {
                if call_expression && call_expression.kind == .IDENT {
                    call_ident := cast(*Code_Ident) call_expression;
                    resolved_call_expression = find_marked_unique_header(plugin, call_ident.name);
                }

                if !resolved_call_expression {
                    compiler_report(plugin, "Thread safety marked functions cannot make non-compile time function calls, as they cannot be safety checked. Alternatively there seems to be a bug with for_expansions where the body contents can't be recursed.\n\nNOTE: If you have a safety marked function with a unique name, it will work as a temporary workaround.", subexpression.location, .ERROR_CONTINUABLE);
                    continue;
                }
            }

            if resolved_call_expression && resolved_call_expression.kind == .PROCEDURE_HEADER {
                resolved_header := cast(*Code_Procedure_Header) resolved_call_expression;

                found_isolated := false;
                found_safe := false;
                for note: resolved_header.notes {
                    if equal_nocase(note.text, "thread_isolated") || equal_nocase(note.text, "thread") {
                        found_isolated = true;
                    } else if equal_nocase(note.text, "thread_safe") {
                        found_safe = true;
                    }
                }

                if found_isolated {
                    if !validate_unlocked(plugin, resolved_header, visited, mutex_options, locked_mutexes, maybe_tprint("%_%", resolved_header.name, resolved_header.kind), maybe_tprint("%\t", precursor)) {
                        return false;
                    }

                    if !resolved_header.body_or_null {
                        compiler_report(plugin, "Thread safety marked header did not have a body.", subexpression.location);
                        return false;
                    }

                    if !validate_unlocked(plugin, resolved_header.body_or_null, visited, mutex_options, locked_mutexes, maybe_tprint("%_%", resolved_header.name, resolved_header.kind), maybe_tprint("%\t", precursor)) {
                        return false;
                    }
                } else if found_safe {
                    #if DEBUG then print(precursor);
                    #if DEBUG then print("\tThread safe: %\n\n", resolved_header.name);
                } else if is_relevant_module(plugin, resolved_header.location) {
                    if locked_mutexes.count == 0 {
                        compiler_report(plugin, "Calling a non-thread safe function from a thread safe function in a thread safety checked module. Without a locked mutex.", subexpression.location, .ERROR_CONTINUABLE);
                        continue;
                    }

                    options := find_or_add(mutex_options, resolved_header);
                    if options.count == 0 {
                        // if there aren't yet any required mutexes, then add all of our locked mutexes
                        array_add(options, ..(locked_mutexes.*));
                    } else {
                        i := 0;
                        while i < options.count {
                            // if the optional mutex isn't currently locked, we remove it from the requirement list as it's no longer a valid lock holder
                            if !array_find(locked_mutexes.*, options.*[i]) {
                                array_ordered_remove_by_index(options, i);
                            } else {
                                i += 1;
                            }
                        }

                        // if there are no more optional mutexes left after locked mutex intersection, then it's no longer a valid call
                        if options.count == 0 {
                            compiler_report(plugin, "Calling a non-thread safe function and all mutexes that were expected to be locked, as indicated by other calls to this same function, weren't.", subexpression.location, .ERROR_CONTINUABLE);
                            continue;
                        }
                    }

                    #if DEBUG then print(precursor);
                    #if DEBUG then print("\tHeader % was safe due to mutex locks: %\n", resolved_header.name, locked_mutexes.*);
                } else {
                    locked_mutex := get_maybe_locked_mutex(plugin, resolved_header, subexpression_call);
                    if locked_mutex {
                        if array_find(locked_mutexes.*, locked_mutex) {
                            compiler_report(plugin, "Locking the same mutex twice before unlocking. If this is wrong and you have special mutex logic, then don't give your thread_unlocked a name.", subexpression.location, .ERROR_CONTINUABLE);
                            continue;
                        }

                        #if DEBUG then compiler_report(plugin, "Found locked mutex:", subexpression.location, .INFO);
                        
                        array_add(locked_mutexes, locked_mutex);
                    } else {
                        unlocked_mutex := get_maybe_unlocked_mutex(plugin, resolved_header, subexpression_call);
                        if unlocked_mutex {
                            if !array_find(locked_mutexes.*, unlocked_mutex) {
                                compiler_report(plugin, "Unlocking a mutex that's not locked. If this is wrong and you have special mutex logic, then don't give your thread_unlocked a name.", subexpression.location, .ERROR_CONTINUABLE);
                                continue;
                            }

                            #if DEBUG then compiler_report(plugin, "Found unlocked mutex:", subexpression.location, .INFO);

                            array_ordered_remove_by_value(locked_mutexes, unlocked_mutex);
                        }
                    }

                    #if DEBUG then print("\n");
                    #if DEBUG then print(precursor);
                    #if DEBUG then print("\tSkipping due to module: %\n\n", resolved_header.name);
                }
            }
        } if subexpression.kind == .IF && (cast(*Code_If) subexpression).is_static {
            // we want to try to skip static ifs if the result is known at compile time and simple
            code_if := cast(*Code_If) subexpression;
            #if DEBUG then print(precursor);
            #if DEBUG then print("\tStsatic if: %\n", code_if.*);

            if code_if.condition && code_if.condition.kind == .IDENT {
                condition_ident := cast(*Code_Ident) code_if.condition;

                #if DEBUG then print(precursor);
                #if DEBUG then print("\tStatic ident: %\n", condition_ident.*);
                
                if condition_ident.resolved_declaration && condition_ident.resolved_declaration.expression {
                    expression := condition_ident.resolved_declaration.expression;
                    if expression.kind == .LITERAL {
                        literal := cast(*Code_Literal) expression;
                        go_then := literal.value_type == .TRUE;

                        // these are the only cases where we will essentially skip processing the if subexpression
                        if go_then {
                            if !validate_unlocked(plugin, code_if.then_block, visited, mutex_options, locked_mutexes, maybe_tprint("%.%", identifier, code_if.then_block.kind), maybe_tprint("%\t", precursor)) {
                                return false;
                            }
                        } else {
                            if !validate_unlocked(plugin, code_if.else_block, visited, mutex_options, locked_mutexes, maybe_tprint("%.%", identifier, code_if.else_block.kind), maybe_tprint("%\t", precursor)) {
                                return false;
                            }
                        }

                        continue;
                    }
                }
            } else if code_if.condition {
                #if DEBUG then print(precursor);
                #if DEBUG then print("\tUnhandled static condition: %\n", code_if.condition.*);
            }

            // if we can't evaluate the static if statement we just continue
            if !validate_unlocked(plugin, subexpression, visited, mutex_options, locked_mutexes, maybe_tprint("%.%", identifier, subexpression.kind), maybe_tprint("%\t", precursor)) {
                return false;
            }
        } else {
            if !validate_unlocked(plugin, subexpression, visited, mutex_options, locked_mutexes, maybe_tprint("%.%", identifier, subexpression.kind), maybe_tprint("%\t", precursor)) {
                return false;
            }
        }
    }

    return true;
}

is_relevant_module :: (plugin: *ThreadSafetyPlugin, location: Code_Node.Location) -> bool {
    enclosing_load := location.enclosing_load;
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

compiler_report :: (plugin: *ThreadSafetyPlugin, error_text: string, location: Code_Node.Location, mode := Report.ERROR) {
    loc: Source_Code_Location;
    loc.fully_pathed_filename = location.enclosing_load.fully_pathed_filename;
    loc.line_number           = location.l0;
    loc.character_number      = location.c0;

    compiler_report(error_text, loc, mode);

    if !plugin.failed && (mode == .ERROR || mode == .ERROR_CONTINUABLE) {
        plugin.failed = true;
    }
}

find_marked_unique_header :: (plugin: *ThreadSafetyPlugin, name: string) -> *Code_Procedure_Header, int {
    for header, index: plugin.marked_unique_headers {
        if header.name == name {
            return header, index;
        }
    }

    return null, -1;
}

get_maybe_locked_mutex :: (plugin: *ThreadSafetyPlugin, header: *Code_Procedure_Header, call: *Code_Procedure_Call) -> *Code_Node {
    if header.name != "lock" {
        return null;
    }

    enclosing_load := header.base.location.enclosing_load;
    if !enclosing_load || !enclosing_load.enclosing_import {
        return null;
    }

    module_name := enclosing_load.enclosing_import.module_name;
    if module_name != "Thread" {
        return null;
    }

    arguments := call.arguments_unsorted;
    if arguments.count != 1 {
        compiler_report(plugin, "Found a mutex unlock with more than 1 argument.", call.location);
        return null;
    }

    argument := arguments[0];
    if argument.expression && argument.expression.kind == .UNARY_OPERATOR {
        unary := cast(*Code_Unary_Operator) argument.expression;

        ident := get_declaration_ident(plugin, unary);
        if ident {
            return ident.resolved_declaration;
        }
    }

    return null;
}

get_maybe_unlocked_mutex :: (plugin: *ThreadSafetyPlugin, header: *Code_Procedure_Header, call: *Code_Procedure_Call) -> *Code_Node {
    if header.name != "unlock" {
        return null;
    }

    enclosing_load := header.base.location.enclosing_load;
    if !enclosing_load || !enclosing_load.enclosing_import {
        return null;
    }

    module_name := enclosing_load.enclosing_import.module_name;
    if module_name != "Thread" {
        return null;
    }

    arguments := call.arguments_unsorted;
    if arguments.count != 1 {
        compiler_report(plugin, "Found a mutex unlock with more than 1 argument.", call.location);
        return null;
    }

    argument := arguments[0];
    if argument.expression && argument.expression.kind == .UNARY_OPERATOR {
        unary := cast(*Code_Unary_Operator) argument.expression;

        ident := get_declaration_ident(plugin, unary);
        if ident {
            return ident.resolved_declaration;
        }
    }

    return null;
}

get_declaration_ident :: (plugin: *ThreadSafetyPlugin, unary: *Code_Unary_Operator) -> *Code_Ident {
    while unary.subexpression && unary.subexpression.kind == .UNARY_OPERATOR {
        unary = cast(*Code_Unary_Operator) unary.subexpression;
    }

    if unary.subexpression && unary.subexpression.kind == .IDENT {
        return cast(*Code_Ident) unary.subexpression;
    } else if unary.subexpression && unary.subexpression.kind == .BINARY_OPERATOR {
        return get_declaration_ident(plugin, cast(*Code_Binary_Operator) unary.subexpression);
    }

    return null;
}

get_declaration_ident :: (plugin: *ThreadSafetyPlugin, binary: *Code_Binary_Operator) -> *Code_Ident {
    while binary.right && binary.right.kind == .BINARY_OPERATOR {
        binary = cast(*Code_Binary_Operator) binary.right;
    }

    if binary.right && binary.right.kind == .IDENT {
        return cast(*Code_Ident) binary.right;
    } else if binary.right && binary.right.kind == .UNARY_OPERATOR {
        return get_declaration_ident(plugin, cast(*Code_Unary_Operator) binary.right);
    }

    return null;
}

maybe_tprint :: (format_string: string, args: ..Any) -> string {
    #if DEBUG {
        return tprint(format_string, ..args);
    }

    return "";
}

#import "Basic";
#import "Code_Visit";
#import "Compiler";
#import "Hash_Table";
#import "String";