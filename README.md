
### Thread Safety Notes

This metaprogram will automatically safety check any modules that use any thread safety marking notes.

### Safety Checking Rules

#### @thread_unlocked

`@thread_unlocked` can only call into `@thread_isolated`, or `@thread_safe`.

`@thread_unlocked` should also be your entry point for the thread function. This is where the safety check starts.

`@thread_unlocked` allows you to call into unmarked functions as long as you've locked a mutex. Every call into a given unsafe function must acquire the same mutex lock for a given thread name.

`@thread_unlocked(name)` can be used when you have multiple threads that start and end in sync with each other.

`@thread_unlocked(name)` allows you to have a unique set of allowed mutex locks for a given unsafe callback.

#### @thread_isolated @thread

`@thread_isolated` can only call into `@thread_isolated`, or `@thread_safe`.

`@thread_isolated` can call into unmarked functions when that functions corresponding mutex has been locked.

`@thread` is another alias for `@thread_isolated`.

#### @thread_safe

`@thread_safe` can call into anything.

`@thread_safe` has no rules. It's just implicitly trusted.

---

It wouldn't be that hard to extend this to deadlock detection where you check you're ever dependent on one lock releasing before another happens to be acquired. But I'm not sure if this is always a valid rule?

I could also continue recursing past the first unsafe entry (with a mutex lock) to ensure that any other function calls down the chain use the same mutex lock. Without this, you could use two different mutexes to access the same function but at different points in the stack, where one might be deep enough into unsafe territory to avoid being checked.
