
main :: () {
    init(*mutex);

    function();
} @thread_unlocked

function :: () {
    #if true {
        safe();
    } else {
        unsafe();
    }
} @thread

safe :: () {
    lock(*thing.thing.inner_mutex);
    defer unlock(*thing.thing.inner_mutex);

    unsafe3();
} @thread

unsafe :: () {

}

mutex: Mutex;

#import "Thread";
