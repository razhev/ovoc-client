package main

import (
    "net"
    "testing"
    "time"
    "unsafe"
)

func TestCloseUnblocksReadAndWriteAndIsIdempotent(t *testing.T) {
    for i := 0; i < 100; i++ {
        local, remote := net.Pipe()
        connectionsMu.Lock()
        id := nextID
        nextID++
        CloakConnections[id] = local
        connectionsMu.Unlock()
        written, read := make(chan int, 1), make(chan int, 1)
        go func() { b := byte(42); written <- Cloak_write(id, unsafe.Pointer(&b), 1) }()
        go func() { b := byte(0); read <- Cloak_read(id, unsafe.Pointer(&b), 1) }()
        Cloak_close_connection(id)
        Cloak_close_connection(id)
        for _, ch := range []chan int{written, read} {
            select {
            case result := <-ch:
                if result != -1 { t.Fatalf("closed connection returned %d", result) }
            case <-time.After(time.Second):
                t.Fatal("close did not unblock I/O")
            }
        }
        remote.Close()
    }
}

func TestClosingOneConnectionPreservesAnother(t *testing.T) {
    first, peer1 := net.Pipe()
    second, peer2 := net.Pipe()
    defer peer1.Close()
    defer peer2.Close()
    connectionsMu.Lock()
    id := nextID
    nextID += 2
    CloakConnections[id], CloakConnections[id+1] = first, second
    connectionsMu.Unlock()
    defer Cloak_close_connection(id+1)
    Cloak_close_connection(id)
    go func() { peer2.Write([]byte{42}) }()
    second.SetReadDeadline(time.Now().Add(time.Second))
    b := byte(0)
    if Cloak_read(id+1, unsafe.Pointer(&b), 1) != 1 || b != 42 {
        t.Fatal("closing another connection damaged live socket")
    }
}
