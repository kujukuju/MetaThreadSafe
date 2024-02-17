
main :: () {
    init(*thing.mutex);
    init(*thing.other_mutex);
    init(*thing.thing.inner_mutex);

    function();
    // not_allowed();
    allowed();
} @thread_unlocked

function :: () {
    lock(*thing.mutex);
    defer unlock(*thing.mutex);

    unsafe();
} @thread

not_allowed :: () {
    lock(*thing.mutex);
    defer unlock(*thing.other_mutex);

    unsafe2();
} @thread

allowed :: () {
    lock(*thing.thing.inner_mutex);
    defer unlock(*thing.thing.inner_mutex);

    unsafe3();
} @thread

unsafe :: () {

}

unsafe2 :: () {

}

unsafe3 :: () {

}

InnerThing :: struct {
    inner_mutex: Mutex;
}

Thing :: struct {
    mutex: Mutex;
    other_mutex: Mutex;
    thing: InnerThing;
}

thing: Thing;

#import "Thread";
