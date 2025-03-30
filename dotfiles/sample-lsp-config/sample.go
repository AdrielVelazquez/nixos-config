package main

import "fmt"

type test struct {
	a string
}

func main() {
	i := "string"
	h := 1
	for v := range 10 {
		fmt.Println(v)
		h += v
		fmt.Println(v + h)

	}
	r := test{a: "adriel"}
	fmt.Println(r.a)
}
