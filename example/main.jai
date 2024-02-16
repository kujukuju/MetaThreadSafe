#run,stallable {
    set_build_options_dc(.{do_output = false});

    w := compiler_create_workspace();
    options := get_build_options();
    options.output_type = .EXECUTABLE;
    options.output_executable_name = "example";
    options.debug_for_expansions = true;

    set_build_options(options, w);

    MetaThreadSafe :: #import "MetaThreadSafe";
    plugin := MetaThreadSafe.get_plugin();
    
    intercept_flags: Intercept_Flags;
    plugin.before_intercept(plugin, *intercept_flags);

    compiler_begin_intercept(w, intercept_flags);

    add_build_file("for_expansion_example.jai", w);

    while true {
        message := compiler_wait_for_message();

        plugin.message(plugin, message);

        if message.kind == .COMPLETE break;
    }

    compiler_end_intercept(w);

    plugin.shutdown(plugin);
}

#import "Basic";
#import "Compiler";
#import "Hash_Table";
#import "String";
