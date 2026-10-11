package main

import (
	"net"
	"sync"
	"testing"
	"time"
	"unsafe"

	"github.com/cbeuw/connutil"
)

// Each test installs connections before starting workers and waits for all
// workers before returning. Production registry accesses are exercised through
// the exported C entry points, so these tests also compile against the base.
func registerTestConnection(connection net.Conn) int {
	// Preserve production fd behavior while preventing this unit test from
	// closing an unrelated process descriptor through the legacy close path.
	fd = -1
	id := nextID
	nextID++
	CloakConnections[id] = connection
	return id
}

func waitResult(t *testing.T, result <-chan int) {
	t.Helper()
	select {
	case n := <-result:
		if n != -1 {
			t.Fatalf("closed connection returned %d, want -1", n)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("close did not unblock I/O")
	}
}

func TestLateWriteAfterCloseReturnsError(t *testing.T) {
	connection, peer := net.Pipe()
	defer peer.Close()
	id := registerTestConnection(connection)
	Cloak_close_connection(id)
	b := byte(42)
	if n := Cloak_write(id, unsafe.Pointer(&b), 1); n != -1 {
		t.Fatalf("write after close returned %d, want -1", n)
	}
	if n := Cloak_read(id, unsafe.Pointer(&b), 1); n != -1 {
		t.Fatalf("read after close returned %d, want -1", n)
	}
	Cloak_close_connection(id)
}

type observedConnection struct {
	net.Conn
	readStarted, writeStarted chan struct{}
}

func (connection *observedConnection) Read(b []byte) (int, error) {
	close(connection.readStarted)
	return connection.Conn.Read(b)
}

func (connection *observedConnection) Write(b []byte) (int, error) {
	close(connection.writeStarted)
	return connection.Conn.Write(b)
}

func waitStarted(t *testing.T, started <-chan struct{}) {
	t.Helper()
	select {
	case <-started:
	case <-time.After(2 * time.Second):
		t.Fatal("I/O worker did not enter connection")
	}
}

func TestCloseUnblocksActiveReadAndWrite(t *testing.T) {
	for attempt := 0; attempt < 100; attempt++ {
		// Cloak_dial uses this buffered pipe with the same 10 KiB limit.
		// Fill past its soft limit so the next native write must block.
		local, peer := connutil.LimitedAsyncPipe(10 * 1024)
		if _, err := local.Write(make([]byte, 10*1024+1)); err != nil {
			t.Fatal(err)
		}
		connection := &observedConnection{local, make(chan struct{}), make(chan struct{})}
		id := registerTestConnection(connection)
		written, read := make(chan int, 1), make(chan int, 1)
		go func() {
			b := byte(42)
			written <- Cloak_write(id, unsafe.Pointer(&b), 1)
		}()
		go func() {
			b := byte(0)
			read <- Cloak_read(id, unsafe.Pointer(&b), 1)
		}()
		waitStarted(t, connection.readStarted)
		waitStarted(t, connection.writeStarted)
		Cloak_close_connection(id)
		waitResult(t, written)
		waitResult(t, read)
		peer.Close()
	}
}

func TestConcurrentRegistryLookupAndClose(t *testing.T) {
	for attempt := 0; attempt < 100; attempt++ {
		connection, peer := net.Pipe()
		id := registerTestConnection(connection)
		start := make(chan struct{})
		results := make(chan int, 16)
		var closed sync.WaitGroup
		for worker := 0; worker < 16; worker++ {
			go func(write bool) {
				<-start
				b := byte(42)
				if write {
					results <- Cloak_write(id, unsafe.Pointer(&b), 1)
				} else {
					results <- Cloak_read(id, unsafe.Pointer(&b), 1)
				}
			}(worker%2 == 0)
		}
		closed.Add(2)
		for worker := 0; worker < 2; worker++ {
			go func() {
				defer closed.Done()
				<-start
				Cloak_close_connection(id)
			}()
		}
		close(start)
		for worker := 0; worker < 16; worker++ {
			waitResult(t, results)
		}
		closed.Wait()
		peer.Close()
	}
}
