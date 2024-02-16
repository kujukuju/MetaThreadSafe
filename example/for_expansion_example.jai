
main :: () {
    call_chain_a();
}

call_chain_a :: () {
    for thing: expandable {
        call_chain_b();
    }
}

call_chain_b :: () {
    print("Never reaches.\n");
}

Expandable :: struct {

}

expandable: Expandable;

for_expansion :: (expandable: *Expandable, body: Code, flags: For_Flags) #expand {
    `it_index: int = 0;
    `it: int = 0;
    #insert body;
}

#import "Basic";
