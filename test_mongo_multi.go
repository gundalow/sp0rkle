package main
import (
	"fmt"
	"gopkg.in/mgo.v2"
)
func main() {
	info, err := mgo.ParseURL("host1,host2")
	if err != nil {
		fmt.Printf("Error: %v\n", err)
	} else {
		fmt.Printf("Info Addrs: %v\n", info.Addrs)
	}
}
