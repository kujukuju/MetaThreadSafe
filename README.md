
### Safety Checking Rules

This metaprogram will automatically typcheck any modules that use any thread safety type notes.

### Valid Thread Safety Notes

#### @thread_unlocked

`@thread_unlocked` can only call into `@thread_isolated`, `@thread_locked`, or `@thread_safe`.

`@thread_unlocked` should also be your entry point for the thread function. This is where the safety check starts.

#### @thread_isolated

`@thread_isolated` can only call into `@thread_isolated`, `@thread_locked`, or `@thread_safe`.

#### @thread_locked

`@thread_locked` can call into anything.

`@thread_locked` isn't allowed to call back into itself at any point in the stack. (Not yet true.)

`@thread_locked` must call lock on a mutex or wait_for on a semaphore.

#### @thread_safe

`@thread_safe` can call into anything.

`@thread_safe` has no rules. It's just implicitly trusted.