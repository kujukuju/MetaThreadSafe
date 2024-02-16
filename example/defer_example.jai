
main :: () {
    init(*mutex);

    example_valid_a();
    example_valid_b();

    example_invalid_a();
    example_invalid_b();
    example_invalid_c();
} @thread_unlocked

example_valid_a :: () {
    lock(*mutex);
    defer unlock(*mutex);

    unsafe();
} @thread

example_valid_b :: () {
    lock(*mutex);
    defer unlock(*mutex);

    if true {
        unsafe();
    }
} @thread

example_invalid_a :: () {
    if true {
        lock(*mutex);
        defer unlock(*mutex);
    }

    unsafe();
} @thread

example_invalid_b :: () {
    for 0..1 {
        lock(*mutex);
        defer unlock(*mutex);

        unsafe();
    }

    unsafe();
} @thread;

example_invalid_c :: () {
    {
        lock(*mutex);
        defer unlock(*mutex);

        unsafe();
    }

    unsafe();
} @thread

unsafe :: () {
    
}

mutex: Mutex;

#import "Thread";
