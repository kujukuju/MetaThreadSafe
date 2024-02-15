
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
} @thread_unlocked

locked_call :: () {
    lock(*mutex);
    defer unlock(*mutex);
    
    thing := pow(2.0, 2.0);
    unsafe_call();
} @thread_locked

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

mutex: Mutex;

#import "Basic";
#import "Math";
#import "Thread";