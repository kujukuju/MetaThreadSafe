
main :: () {
    init(*mutex_a);
    init(*mutex_b);

    thread_entry_a();
    thread_entry_b();
}



thread_entry_a :: () {
    // this one is ok
    isolated_a1();
    isolated_a2();
    isolated_a3();
} @thread_unlocked(thread_a)

isolated_a1 :: () {
    lock(*mutex_a);
    unsafe_function_a();
    unlock(*mutex_a);

    lock(*mutex_b);
    defer unlock(*mutex_b);

    unsafe_function_b();
} @thread_isolated

isolated_a2 :: () {
    lock(*mutex_a);
    unsafe_function_a();
    unlock(*mutex_a);

    lock(*mutex_b);
    unsafe_function_b();
    unlock(*mutex_b);
} @thread_isolated

isolated_a3 :: () {
    lock(*mutex_a);
    defer unlock(*mutex_a);

    unsafe_function_a();
} @thread_isolated



thread_entry_b :: () {
    // this one locks using 2 different mutexes, not okay
    isolated_b1();
    isolated_b2();
} @thread_unlocked(thread_b)

isolated_b1 :: () {
    lock(*mutex_a);
    defer unlock(*mutex_a);

    unsafe_function_b();
} @thread_isolated

isolated_b2 :: () {
    lock(*mutex_b);
    defer unlock(*mutex_b);

    unsafe_function_b();
} @thread_isolated



unsafe_function_a :: () {

}

unsafe_function_b :: () {

}

mutex_a: Mutex;
mutex_b: Mutex;

#import "Basic";
#import "Thread";