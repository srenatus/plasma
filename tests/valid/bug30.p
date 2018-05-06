# vim: ft=plasma
# This is free and unencumbered software released into the public domain.
# See ../LICENSE.unlicense

module bug

export main
import IO

# TODO:
#  Need to implement and test HO values in type arguments

func main() uses IO -> Int {
    print!(join(", ", map(int_to_string, [1, 2, 3])) ++ "\n")

    return 0
}

func map(f : func(x) -> (y), l : List(x)) -> List(y) {
    match (l) {
        [] ->       { return [] }
        [x | xs] -> { return [f(x) | map(f, xs)] }
    }
}

func join(j : String, l0 : List(String)) -> String {
    match (l0) {
        [] ->       { return "" }
        [x | l] -> {
            match (l) {
                [] ->      { return x }
                [_ | _] -> { return x ++ j ++ join(j, l) }
            }
        }
    }
}