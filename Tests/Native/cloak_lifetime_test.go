package main

import (
	"bytes"
	"io"
	"net"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/cbeuw/Cloak/internal/client"
	log "github.com/sirupsen/logrus"
)

// These tests use the real C entrypoints and also compile against build 11.
func TestCloseMustNotCloseUnrelatedSocket(t *testing.T) {
	pair, err := syscall.Socketpair(syscall.AF_UNIX, syscall.SOCK_STREAM, 0)
	if err != nil {
		t.Fatal(err)
	}
	defer syscall.Close(pair[0])
	defer syscall.Close(pair[1])
	local, peer := net.Pipe()
	defer peer.Close()
	id := registerTestConnection(local)
	// A newer dial or OS descriptor reuse can replace the old connection's fd.
	fd = pair[0]
	Cloak_close_connection(id)
	if _, err := syscall.Write(pair[0], []byte{42}); err != nil {
		t.Fatalf("closing old Cloak connection closed unrelated live socket: %v", err)
	}
}

func listenForCloak(t *testing.T) *net.TCPListener {
	t.Helper()
	listener, err := net.ListenTCP("tcp4", &net.TCPAddr{IP: net.IPv4(127, 0, 0, 1)})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { listener.Close() })
	host, port, _ := net.SplitHostPort(listener.Addr().String())
	singleplexTCPConfig = client.RawConfig{
		ServerName: "example.com", ProxyMethod: "openvpn", EncryptionMethod: "plain",
		UID: bytes.Repeat([]byte{1}, 16), PublicKey: bytes.Repeat([]byte{2}, 32), NumConn: 1,
		RemoteHost: host, RemotePort: port, LocalHost: "127.0.0.1", LocalPort: "9999",
	}
	return listener
}

func acceptHello(t *testing.T, listener *net.TCPListener) net.Conn {
	t.Helper()
	listener.SetDeadline(time.Now().Add(2 * time.Second))
	connection, err := listener.Accept()
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { connection.Close() })
	connection.SetReadDeadline(time.Now().Add(2 * time.Second))
	// Read exactly one TLS record, so EOF below is about cancellation, not data.
	header := make([]byte, 5)
	if _, err := io.ReadFull(connection, header); err != nil {
		t.Fatal(err)
	}
	payload := make([]byte, int(header[3])<<8|int(header[4]))
	if _, err := io.ReadFull(connection, payload); err != nil {
		t.Fatal(err)
	}
	return connection
}

func TestCloseStopsRetrying(t *testing.T) {
	hook := retryHook{make(chan struct{}, 1)}
	logger := log.StandardLogger()
	previousHooks := logger.ReplaceHooks(make(log.LevelHooks))
	logger.AddHook(hook)
	defer logger.ReplaceHooks(previousHooks)
	listener := listenForCloak(t)
	id := Cloak_dial()
	defer Cloak_close_connection(id)
	connection := acceptHello(t, listener)
	connection.Close() // Force a failed handshake and the normal three-second retry.
	select {
	case <-hook.failed:
	case <-time.After(2 * time.Second):
		t.Fatal("handshake failure was not processed")
	}
	Cloak_close_connection(id)
	listener.SetDeadline(time.Now().Add(3500 * time.Millisecond))
	if next, err := listener.Accept(); err == nil {
		next.Close()
		t.Fatal("closed Cloak connection started another remote dial")
	} else if timeout, ok := err.(net.Error); !ok || !timeout.Timeout() {
		t.Fatalf("listener unexpectedly failed: %v", err)
	}
}

type retryHook struct{ failed chan struct{} }

func (retryHook) Levels() []log.Level { return []log.Level{log.ErrorLevel} }
func (h retryHook) Fire(entry *log.Entry) error {
	if strings.Contains(entry.Message, "Failed to prepare connection") || strings.Contains(entry.Message, "Failed to establish Cloak connection") {
		select {
		case h.failed <- struct{}{}:
		default:
		}
	}
	return nil
}

func TestClosingOldSessionPreservesNewHandshake(t *testing.T) {
	listener := listenForCloak(t)
	oldID := Cloak_dial()
	defer Cloak_close_connection(oldID)
	oldRemote := acceptHello(t, listener)
	newID := Cloak_dial()
	defer Cloak_close_connection(newID)
	newRemote := acceptHello(t, listener)
	Cloak_close_connection(oldID)
	oldRemote.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := oldRemote.Read(make([]byte, 1)); err != io.EOF {
		t.Fatalf("old handshake was not cancelled: %v", err)
	}
	newRemote.SetReadDeadline(time.Now().Add(100 * time.Millisecond))
	if _, err := newRemote.Read(make([]byte, 1)); err == nil {
		t.Fatal("unexpected handshake data")
	} else if timeout, ok := err.(net.Error); !ok || !timeout.Timeout() {
		t.Fatalf("closing old session affected new handshake: %v", err)
	}
	Cloak_close_connection(newID)
	newRemote.SetReadDeadline(time.Now().Add(time.Second))
	if _, err := newRemote.Read(make([]byte, 1)); err != io.EOF {
		t.Fatalf("new handshake was not cancelled: %v", err)
	}
}
