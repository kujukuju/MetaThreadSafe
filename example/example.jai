
main :: () {
    init(*mutex);
    multithreaded_method();
}

multithreaded_method :: () {
    value := 1.0;

    isolated_call();

    if value == 1.0 {
        locked_call();
    }

    for i: 0..1 {
        safe_call();
    }

    call_chain_macro_start();
} @thread_unlocked

locked_call :: () {
    lock(*mutex);
    defer unlock(*mutex);
    
    thing := pow(2.0, 2.0);
    unsafe_call();
} @thread

isolated_call :: () {

} @thread_isolated

safe_call :: () {
    totally_not_safe_actually_but_oh_well();
} @thread_safe

unsafe_call :: () {
    print("woo\n");
}

totally_not_safe_actually_but_oh_well :: () {
    print("alright\n");
}

call_chain_macro_start :: () #expand {
    // normal_macro(call_chain_a());
    for *thing: expandable {
        call_chain_a();
    }
} @thread_isolated

call_chain_a :: () {
    call_chain_b();
} @thread_isolated

call_chain_b :: () {
    call_chain_c();
} @thread_isolated

call_chain_c :: () {
    call_chain_d_invalid();
} @thread_isolated

call_chain_c_non_compile_time :: () {
    callable: #type ();
    if true {
        callable := valid_but_compile_time;
    }

    if callable {
        callable();
    }
} @thread_isolated

call_chain_d_invalid :: () {

}

valid_but_compile_time :: () {

} @thread_safe

Expandable :: struct {

}

expandable: Expandable;

for_expansion :: (expandable: *Expandable, body: Code, flags: For_Flags) #expand {
    `it_index: int = 0;
    `it: int = 0;
    #insert body;
}

mutex: Mutex;
table: Table(u64, u64);

#import "Basic";
#import "Math";
#import "Thread";
#import "Hash_Table";