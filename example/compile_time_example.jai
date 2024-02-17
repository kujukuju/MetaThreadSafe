
main :: () {
    init(*mutex);

    function(true);
} @thread_unlocked

function :: ($async: bool) {
    #if async {
        safe();
    } else {
        unsafe();
    }
} @thread

safe :: () {
    lock(*mutex);
    defer unlock(*mutex);

    unsafe();
} @thread

unsafe :: () {

}

mutex: Mutex;

#import "Thread";
